# use the pandoc image as the starting point
FROM broadbandforum/pandoc:latest

# install packages and link report.pl to a default search path
RUN apt-get update \
            && apt-get --yes install cpanminus libxml2-dev git python3-pip zip \
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

# install necessary python modules (used for generating JUnit XML)
RUN pip3 install \
    junit_xml

# copy report.pl to /opt/bbf/bin
COPY report.pl /opt/bbf/bin/report.pl

# copy plugins to /opt/bbf/plugins
COPY plugins /opt/bbf/plugins
