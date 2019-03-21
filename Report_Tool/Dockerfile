# use an official perl runtime as a parent image
FROM perl:latest

# install libxml2 and link report.pl to a default search path
RUN apt-get update \
            && apt-get --yes install libxml2-dev \
            && ln -s /opt/bbf/bin/report.pl /usr/local/bin/report.pl \
            && apt-get clean

# install necessary perl modules
RUN cpanm \
    Algorithm::Diff \
    Clone \
    Config::IniFiles \
    Data::Compare \
    File::Compare \
    String::Tokenizer \
    URI::Escape \
    XML::LibXML

# copy report.pl to /opt/bbf/bin
COPY report.pl /opt/bbf/bin/report.pl

# copy plugins to /opt/bbf/plugins
COPY plugins /opt/bbf/plugins
