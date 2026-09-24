#!/usr/bin/env python3
"""Génère le dictionnaire plat de la skill snds-query depuis le dépôt schema-snds.

Source : https://gitlab.com/healthdatahub/applications-du-hdh/schema-snds
(Health Data Hub, licence MPL-2.0). Les fichiers produits sont des dérivés de
cette source et restent sous MPL-2.0 (voir NOTICE et
skills/snds-query/references/dictionnaire/README.md).

Usage (depuis la racine de la skill) :
    git clone --depth 1 https://gitlab.com/healthdatahub/applications-du-hdh/schema-snds.git
    python3 scripts/build-dictionary.py schema-snds                  # régénère references/dictionnaire/
    python3 scripts/build-dictionary.py schema-snds --out /tmp/dico  # version fraîche, hors skill

Produit, dans references/dictionnaire/ (ou --out) (TSV UTF-8, une ligne
par enregistrement, sans guillemets — recherche par grep) :
    tables.tsv          une ligne par table
    variables.tsv       une ligne par variable (table + variable)
    jointures.tsv       clés étrangères déclarées (table -> table référencée)
    nomenclatures.tsv   une ligne par nomenclature (table de valeurs / référentiel)
    valeurs.tsv         codes et libellés des nomenclatures de moins de --max-kb Ko
                        (non écrit si le clone ne contient pas les CSV de nomenclatures,
                        ex. clone partiel limité aux schémas JSON)
    SOURCE.txt          commit et date de la source utilisée
Idempotent : régénère tout à chaque exécution.
"""
import argparse
import csv
import glob
import json
import os
import subprocess
import sys

REPO_URL = "https://gitlab.com/healthdatahub/applications-du-hdh/schema-snds"


def clean(text):
    """Texte sur une seule ligne, sans tabulation (format TSV)."""
    if text is None:
        return ""
    text = str(text).replace("<br/>", " | ").replace("<br>", " | ")
    return " | ".join(part.strip() for part in text.replace("\t", " ").splitlines() if part.strip())


def years(entry):
    """(début, fin, absente) d'une variable ou d'une table, tels que déclarés."""
    missing = sorted(entry.get("dateMissing") or [])
    return entry.get("dateCreated") or "", entry.get("dateDeleted") or "", ",".join(missing)


def write_tsv(path, header, rows):
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\t".join(header) + "\n")
        for row in rows:
            handle.write("\t".join(clean(value) for value in row) + "\n")
    print(f"{os.path.basename(path):18} : {len(rows):6} lignes")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("schema_snds", help="clone local du dépôt schema-snds")
    parser.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                                                      "references", "dictionnaire"))
    parser.add_argument("--max-kb", type=int, default=50,
                        help="taille maximale (Ko) d'une nomenclature dont les valeurs sont embarquées")
    args = parser.parse_args()

    src = args.schema_snds
    if not os.path.isdir(os.path.join(src, "schemas")):
        sys.exit(f"Dossier schemas/ introuvable dans {src}")
    os.makedirs(args.out, exist_ok=True)

    tables, variables, joins = [], [], []
    for path in sorted(glob.glob(os.path.join(src, "schemas", "*", "*.json"))):
        schema = json.load(open(path, encoding="utf-8"))
        name = schema["name"]
        product = os.path.basename(os.path.dirname(path))
        start, end, missing = years(schema.get("history") or {})
        tables.append([product, name, schema.get("title"), ",".join(schema.get("primaryKey") or []),
                       len(schema["fields"]), start, end, missing, schema.get("observation")])
        for field in schema["fields"]:
            f_start, f_end, f_missing = years(field)
            nomenclature = field.get("nomenclature")
            variables.append([name, field["name"], field.get("type"), field.get("type_oracle"),
                              field.get("length"), "" if nomenclature in (None, "-") else nomenclature,
                              f_start, f_end, f_missing, field.get("description"),
                              field.get("observation"), field.get("regle_gestion")])
        for fk in schema.get("foreignKeys") or []:
            ref = fk.get("reference") or {}
            joins.append([name, ",".join(fk.get("fields") or []), ref.get("resource"),
                          ",".join(ref.get("fields") or [])])

    nomenclatures, values, has_csv = [], [], False
    for path in sorted(glob.glob(os.path.join(src, "nomenclatures", "*", "*.json"))):
        schema = json.load(open(path, encoding="utf-8"))
        name = schema["name"]
        folder = os.path.basename(os.path.dirname(path))
        roles = {f.get("role"): f["name"] for f in schema["fields"] if f.get("role")}
        csv_path = path[:-5] + ".csv"
        has_csv = has_csv or os.path.exists(csv_path)
        size_kb = os.path.getsize(csv_path) // 1024 if os.path.exists(csv_path) else ""
        embedded = bool(size_kb != "" and size_kb < args.max_kb and "code" in roles)
        nomenclatures.append([folder, name, schema.get("title"), ",".join(f["name"] for f in schema["fields"]),
                              roles.get("code", ""), roles.get("label", ""), size_kb,
                              "oui" if embedded else "non"])
        if embedded:
            raw = open(csv_path, "rb").read()
            try:
                text = raw.decode("utf-8-sig")
            except UnicodeDecodeError:          # quelques nomenclatures sont en Latin-1
                text = raw.decode("cp1252")
            for row in csv.DictReader(text.splitlines(), delimiter=";"):
                values.append([name, row.get(roles["code"]), row.get(roles.get("label", ""), "")])

    write_tsv(os.path.join(args.out, "tables.tsv"),
              ["produit", "table", "libelle", "cle_primaire", "nb_variables", "debut", "fin", "absente", "observation"],
              tables)
    write_tsv(os.path.join(args.out, "variables.tsv"),
              ["table", "variable", "type", "type_oracle", "longueur", "nomenclature", "debut", "fin", "absente",
               "libelle", "observation", "regle_gestion"],
              variables)
    write_tsv(os.path.join(args.out, "jointures.tsv"),
              ["table", "colonnes", "table_cible", "colonnes_cible"], joins)
    write_tsv(os.path.join(args.out, "nomenclatures.tsv"),
              ["dossier", "nomenclature", "libelle", "colonnes", "colonne_code", "colonne_libelle", "taille_ko",
               "valeurs_embarquees"],
              nomenclatures)
    if has_csv:
        write_tsv(os.path.join(args.out, "valeurs.tsv"), ["nomenclature", "code", "libelle"], values)
    else:
        print("valeurs.tsv        : non régénéré (CSV de nomenclatures absents du clone)")

    try:
        commit = subprocess.check_output(["git", "-C", src, "log", "-1", "--format=%H %cs"], text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        commit = "inconnu (pas un clone git)"
    with open(os.path.join(args.out, "SOURCE.txt"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(f"Source : {REPO_URL}\nCommit : {commit}\nLicence : MPL-2.0 (Mozilla Public License 2.0)\n")
    print(f"Source : {commit}")


if __name__ == "__main__":
    main()
