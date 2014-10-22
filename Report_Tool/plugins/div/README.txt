#!/bin/sh
#
# Data model structure diagrams are created using the BBF report tool with the
# "div" plugin ("div" refers to the HTML div element, which is the basic
# building block)
#
# See also the configuration file div.ini, which should be in the same
# directory as this file
#
# To generate them, "source" this file or do the equivalent manually; you
# may need to adjust the report tool location and the file locations for your
# environment
#
# Once the files have been generated, view them in a browser, resize the
# browser to make them look as good as possible, and then screen-grab an
# image file

# XXX note that this file and the div.ini file will have to be fine-tuned
#     for each case; it's not as easy as it should be...

# location of report tool (or command with which to run it)
report=$HOME/bin/report.pl

# location of TR-104i2 XML
locdir=$HOME/bin/cwmp

# location of published XML files
pubdir=$HOME/bin/cwmp-bbf

# location of not-yet-published files (point to published files if none)
nypdir=$pubdir

# base file name (no extension)
base=tr-104-2-0-0

# alias to run the tool: brd = "BBF Report Div"
alias brd="$report --include=$locdir --include=$nypdir --include=$pubdir --quiet --plugin=div --report=div"

echo ==== overview ====
brd --outfile=$base-overview.html $base.xml

echo ==== voice service general ====
brd --option depth=2 --outfile=$base-voiceservice.html $base.xml

echo ==== voice service level ====
brd --option depth=4 --option voiceservice.enable=1 --option phyinterface.enable=0 --option protocols.enable=0 --option controlplane.enable=0 --outfile=$base-vslevel.html $base.xml

echo ==== physical interfaces ====
brd --option depth=4 --option voiceservice.enable=0 --option phyinterface.enable=1 --option protocols.enable=0 --option controlplane.enable=0 --outfile=$base-phyintf.html $base.xml

echo ==== VoIP ====
brd --option depth=4 --option voiceservice.enable=0 --option phyinterface.enable=0 --option protocols.enable=1 --option controlplane.enable=0 --outfile=$base-voip.html $base.xml

echo ==== control plane applications ====
brd --option depth=4 --option voiceservice.enable=0 --option phyinterface.enable=0 --option protocols.enable=0 --option controlplane.enable=1 --outfile=$base-cpapp.html $base.xml

