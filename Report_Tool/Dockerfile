# use the pandoc image as the starting point
FROM broadbandforum/pandoc:latest

# install packages
RUN apt-get update \
            && apt-get --yes install cpanminus libxml2-dev git python3-pip zip\
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

# install necessary python modules (used for validating XSD v1.1 XML,
# generating JUnit XML, and for the new report tool)
RUN pip3 install -U \
    junit_xml \
    lxml \
    pyxb \
    xmlschema \
    xmltodict

# copy plugins to /opt/bbf/plugins
COPY plugins /opt/bbf/plugins

# copy executables to /opt/bbf/bin
COPY report.pl xmlschema-validate.py /opt/bbf/bin/

# create soft links in /usr/local/bin
RUN ln -s /opt/bbf/bin/report.pl /usr/local/bin \
 && ln -s /opt/bbf/bin/xmlschema-validate.py /usr/local/bin
