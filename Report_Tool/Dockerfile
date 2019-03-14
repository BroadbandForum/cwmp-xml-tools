# use an official perl runtime as a parent image
FROM perl:latest

# build arguments
ARG INSTALL_TEMP

# install libxml2
RUN apt-get update
RUN apt-get --yes install libxml2-dev

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

# create /opt/bbf and /opt/bbf/bin
RUN mkdir -p /opt/bbf /opt/bbf/bin

# copy report.pl to /opt/bbf/bin
COPY report.pl /opt/bbf/bin

# copy the install repository (the default develop branch is assumed to be
# already checked out); this avoids the need to worry about SSH keys
# XXX no; disabled; can't include this in a public Docker image
# ADD $INSTALL_TEMP /opt/bbf/install

# create a soft link so report.pl will be in the executable search path
RUN ln -s /opt/bbf/bin/report.pl /usr/local/bin/report.pl
