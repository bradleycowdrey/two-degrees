"""Builds Resources/Cities.tsv, the city list the apps search when Open-Meteo can't be reached.

From GeoNames (geonames.org, CC BY 4.0): every place with at least 15,000 people (cities15000) and the
names of their states and provinces (admin1CodesASCII). One city per line, most populous first:
name, ASCII name (empty when the same), state or province, country code, latitude, longitude.
Run by .github/workflows/cities.yml. Usage: make_cities.py <download folder> <output file>
"""
import csv
import os
import sys
import urllib.request
import zipfile

BASE = "https://download.geonames.org/export/dump/"


def fetch(folder, name):
    path = os.path.join(folder, name)
    if not os.path.exists(path):
        urllib.request.urlretrieve(BASE + name, path)
    return path


def main(folder, out):
    os.makedirs(folder, exist_ok=True)
    with zipfile.ZipFile(fetch(folder, "cities15000.zip")) as z:
        rows = z.read("cities15000.txt").decode("utf-8").splitlines()
    admin1 = {}
    with open(fetch(folder, "admin1CodesASCII.txt"), encoding="utf-8") as f:
        for line in f:
            code, name = line.split("\t")[:2]
            admin1[code] = name
    cities = []
    for line in rows:
        c = line.split("\t")
        name, ascii_name, lat, lon, cc, a1, pop = c[1], c[2], c[4], c[5], c[8], c[10], int(c[14] or 0)
        cities.append((pop, name, "" if ascii_name == name else ascii_name, admin1.get(f"{cc}.{a1}", ""), cc,
                       f"{float(lat):.4f}", f"{float(lon):.4f}"))
    cities.sort(key=lambda x: -x[0])
    with open(out, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, delimiter="\t", lineterminator="\n", quoting=csv.QUOTE_NONE, escapechar="\\")
        for city in cities:
            w.writerow(city[1:])
    print(f"{len(cities)} cities, {os.path.getsize(out) // 1024} KB")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
