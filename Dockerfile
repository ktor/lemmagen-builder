FROM docker.elastic.co/elasticsearch/elasticsearch:8.18.4

# Plugin ZIP musi byt v docker/plugin/ pred buildovanim image
ARG PLUGIN_ZIP=elasticsearch-analysis-lemmagen-8.18.0-plugin.zip

# Kopirovanie a instalacia pluginu
COPY plugin/${PLUGIN_ZIP} /tmp/lemmagen-plugin.zip
USER root
RUN elasticsearch-plugin install --batch file:///tmp/lemmagen-plugin.zip \
    && rm /tmp/lemmagen-plugin.zip
USER 1000

# Slovak lexikon
COPY config/lemmagen/sk.lem /usr/share/elasticsearch/config/lemmagen/sk.lem

# Vlastnicke prava - elasticsearch user (uid 1000)
USER root
RUN chown -R 1000:0 /usr/share/elasticsearch/config/lemmagen
USER 1000
