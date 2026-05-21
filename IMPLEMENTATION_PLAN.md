# LemmaGen ES 8.18 - Implementacny plan

## Kontext

Plugin `elasticsearch-analysis-lemmagen` (vhyza) je posledny oficialny release na verziu 8.6.2.
Cielom je zbuildovat funkciu verziu pre ES 8.18.0 zo zdrojoveho kodu pomocou forku.

Slovak lexikon (`sk.lem`) je pod licenciou **CC BY-SA 4.0** - komerčne použiteľný.

---

## Prerekvizity

| Nastroj | Verzia | Poznamka |
|---|---|---|
| Java JDK | 21 | ES 8.x vyzaduje Java 21 |
| Maven | 3.8+ | `mvn --version` |
| Git | any | |
| GitHub account | - | pre fork |
| curl | any | stiahnutie lexikonu |

Overenie:
```bash
java -version     # must be 21.x
mvn --version
git --version
```

---

## Fazy

### Faza 1 - Fork a klonovanie (skript: 01_clone.sh)

1. Na GitHub: fork `vhyza/elasticsearch-analysis-lemmagen` do vlastneho org/usera
2. Spustit `01_clone.sh <github-username>`
3. Vysledok: lokalna kopia forku v `./elasticsearch-analysis-lemmagen/`

### Faza 2 - Priprava zavislosti (skript: 02_prepare_build.sh)

Skript automaticky:
- Zmeni `elasticsearch.version` v `pom.xml` na `8.18.0`
- Zmeni `<version>` projektu v `pom.xml` na `8.18.0`
- Updatuje `plugin-descriptor.properties` (`elasticsearch.version`, `java.version=21`)
- Prida `entitlement-policy.yaml` (vyzadovane ES 8.18 Entitlement security)
- Stahne Slovak lexikon `sk.lem` do `config/lemmagen/`
- Commitne zmeny na novu vetvu `es-8.18`

### Faza 3 - Build

```bash
cd elasticsearch-analysis-lemmagen
mvn clean package -DskipTests
```

Ocakavany vystup:
```
target/releases/elasticsearch-analysis-lemmagen-8.18.0-plugin.zip
```

Ak build zlyha na Java API zmenach - pozri sekciu "Troubleshooting" nizsie.

### Faza 4 - Instalacia a test

```bash
# Instalacia pluginu
$ES_HOME/bin/elasticsearch-plugin install \
  file:///path/to/elasticsearch-analysis-lemmagen-8.18.0-plugin.zip

# Kopirovanie lexikonu
mkdir -p $ES_HOME/config/lemmagen
cp config/lemmagen/sk.lem $ES_HOME/config/lemmagen/

# Restart ES
sudo systemctl restart elasticsearch

# Test
curl -X PUT "localhost:9200/test-sk" -H "Content-Type: application/json" -d '{
  "settings": {
    "analysis": {
      "filter": {
        "sk_lemma": { "type": "lemmagen", "lexicon": "sk" }
      },
      "analyzer": {
        "slovak": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase", "sk_lemma", "asciifolding"]
        }
      }
    }
  }
}'

curl -X GET "localhost:9200/test-sk/_analyze?pretty" \
  -H "Content-Type: application/json" \
  -d '{"analyzer": "slovak", "text": "slovenských republík"}'
```

Ocakavany vysledok:
```json
{ "tokens": [{ "token": "slovensky", ... }, { "token": "republika", ... }] }
```

---

## Troubleshooting

### Compile error: TokenFilterFactory interface

ES 8.x zmenilo interny API pre `TokenFilterFactory`. Ak build zlyha, skontroluj:

```java
// Stary podpis (pre-8.x)
public TokenStream create(TokenStream tokenStream)

// Novy podpis (8.x)
public TokenStream normalize(TokenStream tokenStream)
```

Subor na opravu: `src/main/java/org/elasticsearch/index/analysis/LemmagenFilterFactory.java`

Porovnaj s `analysis-icu` pluginom v rovnakej verzii ES ako referenciu.

### Chyba: "Unknown properties for plugin"

Skontroluj `plugin-descriptor.properties` - nesmu byt extra kluce ktore ES 8.18 nepodporuje.
Odstrán `type=` ak tam je (bol pridany v starej verzii, v 8.4+ sposobuje chybu).

### Chyba: NotEntitledException pri runtime

ES 8.18 pouziva Entitlement security. Skontroluj `entitlement-policy.yaml`:
- Plugin cita subory z `config/lemmagen/` - vyzaduje `files` entitlement
- Skript 02 tento subor prida automaticky, ale cesta musi sediet s realnym ES config dir

### Maven dependency resolution zlyha

ES 8.18 artefakty su na `artifacts.elastic.co`, nie na Maven Central.
Skontroluj `pom.xml` ze obsahuje Elastic repository:

```xml
<repositories>
  <repository>
    <id>elastic-releases</id>
    <url>https://artifacts.elastic.co/maven</url>
  </repository>
</repositories>
```

Skript 02 toto prida automaticky.

---

## Poznamky

- SK lexikon je CC BY-SA 4.0 - pri redistribucii treba uviest atribuciu `vhyza/lemmagen-lexicons`
- Fork udrzuj synchronizovany s upstream pri buducich ES upgradoch (zmena len verzie v pom.xml)
- Pre CI/CD: build je deterministicky, mozno zaradit do pipeline s parametrom `ES_VERSION`
