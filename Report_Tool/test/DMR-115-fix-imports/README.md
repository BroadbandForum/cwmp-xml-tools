# Introduction

This illustrates the problem to be solved:
 
```   
% pwd
/Users/william/Development/install/default/cwmp
```

```
% report.pl tr-181-2-13-usp.xml
(W) tr-181-2-13-0-usp.xml: import tr-181-2-common.xml: spec is
        urn:broadband-forum-org:tr-181-2-14-0
        (doesn't match urn:broadband-forum-org:tr-181-2-13)
(F) {tr-181-2-14-0-common}Device:2.13: model not found
```

The import finds the latest amendment but this is the wrong file. It needs to look for the amendment that matches the import spec (if there is one).

The problem arises from the need for this to work in source directories as well as in release directories.

# Notes

* Don't want to have to name files `tr-nnn-...` (this is currently assumed by the file parsing logic)
