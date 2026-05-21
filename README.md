# LemmaGen ES 8.19 - Slovak Analyzer

## Adresar

```
lemmagen-es819/
├── IMPLEMENTATION_PLAN.md      <- implementacny plan
├── 01_clone.sh                 <- fork + klonovanie
├── 02_prepare_build.sh         <- patch zavislosti + build prep
├── 03_test.sh                  <- test suite
└── docker/
    ├── Dockerfile              <- custom ES image s pluginom
    ├── docker-compose.yml      <- ES + volitelne Kibana
    ├── config/
    │   └── lemmagen/
    │       └── sk.lem          <- Slovak lexikon (skopiruj sem)
    └── plugin/
        └── elasticsearch-analysis-lemmagen-8.19.0-plugin.zip  <- skopiruj sem
```

## Workflow

### 1. Build pluginu

```bash
./01_clone.sh <github-username>
./02_prepare_build.sh
cd elasticsearch-analysis-lemmagen
mvn clean package -DskipTests
```

### 2. Priprava Docker podkladov

```bash
# Plugin ZIP
cp elasticsearch-analysis-lemmagen/target/releases/elasticsearch-analysis-lemmagen-8.19.0-plugin.zip \
   docker/plugin/

# Slovak lexikon
cp lemmagen-lexicons/free/lexicons/sk.lem \
   docker/config/lemmagen/
```

### 3. Spustenie

```bash
cd docker
docker compose up --build -d

# S Kibanou
docker compose --profile kibana up --build -d
```

### 4. Testy

```bash
# Pockat kym ES nabehne (healthcheck)
docker compose ps

# Spustit test suite
cd ..
./03_test.sh

# Alebo s custom hostom/portom
./03_test.sh --host localhost --port 9200
```

### 5. Zastavenie

```bash
cd docker
docker compose down          # zachova volume
docker compose down -v       # zmaze aj data volume
```

## Licencia Slovak lexikonu

`sk.lem` je distribuovany pod **CC BY-SA 4.0**.
Pri komerčnom použití uviesť atribúciu: `vhyza/lemmagen-lexicons`.
