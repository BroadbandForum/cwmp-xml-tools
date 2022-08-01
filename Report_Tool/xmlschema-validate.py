#!/usr/bin/env python3

"""Re-implementation of the xmlschema package's xmlschema-validator script,
with a compatible (but extended) user interface, and improved performance and
error reporting.

If the --include option is set, it shouldn't usually be necessary to set
--schema, version or --location."""

import argparse
import logging
import os
import re
import sys
import urllib.error
import urllib.parse
import warnings

from typing import Any, Dict, List, Optional

# pip install xmlschema
# noinspection PyPep8
import xmlschema

warnings.simplefilter('error')

# XXX lxml _should_ work (and it's desirable, because it includes line number
#     information) but get loads of spurious validation errors when using
#     it; I think there must be a difference between the xml.etree and
#     lxml.etree interfaces
# XXX I have a fix... but it's _much_ slower (should run a profiler, but I
#     suspect that lxml XPath processing is very slow)
using_lxml = False
if using_lxml:
    # noinspection PyPep8Naming
    import lxml.etree as ElementTree
else:
    import xml.etree.ElementTree as ElementTree


# XXX want just the name part; need some utilities / rules / conventions
prog_basename = os.path.basename(__file__)
(prog_root, _) = os.path.splitext(prog_basename)
logger = logging.getLogger(prog_root)


def source_line(error: Any) -> Optional[int]:
    return error.sourceline if \
        isinstance(error, xmlschema.XMLSchemaValidationError) else None


def error_message(error: Any, *,
                  namespaces: Optional[Dict[str, str]] = None,
                  terse: bool = False) -> str:
    # if it's not a schema validation error, just return its string value
    if not isinstance(error, xmlschema.XMLSchemaValidationError):
        return str(error)

    # it has reason and obj attributes
    reason = error.reason
    obj = error.obj

    # if reason is any of the 'ignore' strings, return an empty string
    # - the first one seems spurious, and always to be associated with a
    #   preceding error
    # - the second one unfortunately happens a lot with pre DM v1.10 schemas,
    #   which really slows things down (some validators think that these
    #   schemas are wrong)
    if reason in {"unavailable namespace ''",
                  "XsdFieldSelector(path='@name | @base') field selects "
                  "multiple values!"}:
        logger.debug('ignored error: %s' % reason)
        return ''

    # if terse, just return the reason
    if terse:
        return reason

    # element type check helper (for xml.etree and lxml.etree)
    def is_elem(obj_) -> bool:
        return type(obj_).__name__ in {'Element', '_Element'}

    # attribute type helper (for xml.etree)
    def is_attr_tuple(obj_) -> bool:
        return isinstance(obj_, tuple) and len(obj_) == 2

    # attributes type helper (for lxml.etree)
    def is_attrs_object(obj_) -> bool:
        return type(obj_).__name__ == '_Attrib'

    # element formatting helper
    def elem_text(elem_) -> str:
        attr = (' ' + ' '.join('%s="%s"' % (n, v) for n, v in
                               elem_.attrib.items())) if elem_.attrib else ''
        return '<%s%s>' % (elem_.tag, attr)

    # namespace replacement helper
    def ns_fix(text_: str) -> str:
        if '{' in text_ and namespaces is not None:
            for ns, pfx in namespaces.items():
                if ns in text_:
                    return text_.replace(ns, pfx)
        return text_

    # element
    if is_elem(obj):
        detail = elem_text(obj)

    # attribute
    elif is_attr_tuple(obj):
        # XXX the reason will already include the attribute info
        # name, value = obj
        # elem = ' in %s' % elem_text(error.elem) if hasattr(error, 'elem') \
        #     else ''
        # detail = '%s="%s"%s' % (name, value, elem)
        detail = elem_text(error.elem) if hasattr(error, 'elem') else ''

    # attributes
    elif is_attrs_object(obj):
        detail = elem_text(error.elem) if hasattr(error, 'elem') else ''

    # other
    else:
        detail = str(obj)

    extra = ' in %s' % detail.strip() if detail.strip() else ''
    return ns_fix('%s%s' % (reason, extra))


def report_error(path: str, error: Any, *,
                 namespaces: Optional[Dict[str, str]] = None,
                 terse: bool = False) -> bool:
    sourceline = source_line(error)
    sourceline = ':%d' % sourceline if sourceline is not None else ''
    message = error_message(error, namespaces=namespaces, terse=terse)
    if message == '':
        return False
    else:
        logger.error('%s%s: %s' % (os.path.basename(path), sourceline,
                                   message))
        return True


def find_file(file: str, includes: List[str]) -> Optional[str]:
    # allow the supplied file to be a URL
    parts = urllib.parse.urlparse(file, allow_fragments=False)
    path_part = os.path.basename(parts.path) if parts.scheme else file

    path = path_part
    if os.path.exists(path) or os.path.isabs(path):
        pass
    else:
        for include in includes:
            path = os.path.join(include, path_part)
            if os.path.exists(path):
                break

    if os.path.exists(path):
        logger.debug('file %s found at %s' % (file, path))
        return path
    else:
        logger.error('file %s not found in %s' % (file, includes))
        return None


def get_argparser():
    choices_version = ('1.0', '1.1')
    choices_defuse = ('always', 'remote', 'never')

    default_include = []
    default_location = []
    default_defuse = 'remote'
    default_verbose = 0
    default_loglevel = 0

    assert default_defuse in choices_defuse

    formatter_class = argparse.RawDescriptionHelpFormatter
    arg_parser = argparse.ArgumentParser(prog=prog_basename,
                                         description=__doc__,
                                         fromfile_prefix_chars='@',
                                         formatter_class=formatter_class)

    arg_parser.add_argument('-I', '--include', type=str, action='append',
                            default=default_include,
                            help='search path for schemas and XML files; '
                                 'default: %r' % default_include)
    arg_parser.add_argument('-S', '--schema', type=str,
                            help='path or URL to XSD schema; default: '
                                 'set from first file')
    arg_parser.add_argument('-V', '--version', choices=choices_version,
                            help='XSD schema version; default: set from '
                                 'schema')
    arg_parser.add_argument('-L', '--location', nargs=2, type=str,
                            action='append', default=default_location,
                            help='fallback schema location (URI, '
                                 'URL) tuples; default: set from first '
                                 'file and schema')

    arg_parser.add_argument('--lazy', action='store_true', default=False,
                            help='whether to use lazy validation mode (slower '
                                 'but uses less memory)')
    arg_parser.add_argument('--defuse', choices=choices_defuse,
                            default=default_defuse,
                            help='when to defuse XML data; default: %r' %
                                 default_defuse)

    arg_parser.add_argument('-t', '--terse', action='store_true',
                            help='whether to output terse error messages')
    arg_parser.add_argument('-v', '--verbose', action='count',
                            default=default_verbose,
                            help='verbosity level (can specify it multiple '
                                 'times; alternative to --loglevel); '
                                 'default: %r' % default_verbose)
    arg_parser.add_argument('-l', '--loglevel', type=int,
                            default=default_loglevel,
                            help='logging level (alternative to --verbose); '
                                 'default: %r' % default_loglevel)

    arg_parser.add_argument('file', nargs='+', help='XML files to be '
                                                    'validated')

    return arg_parser


def main(argv=None):
    if argv is None:
        argv = sys.argv

    # get argument parser
    arg_parser = get_argparser()

    # parse arguments
    args = arg_parser.parse_args(argv[1:])
    loglevel_map = {0: logging.WARNING, 1: logging.INFO, 2: logging.DEBUG}

    # the original xmlschema-validate maps verbose=2 to INFO, so this preserves
    # this behavior
    loglevel = loglevel_map[max(args.verbose - 1, args.loglevel)]
    logging.basicConfig(level=loglevel)

    # note whether or not we're using lxml
    logger.debug('%susing lxml' % ('' if using_lxml else 'not '))

    # convert location tuples to a dict
    args.location = {namespace: path for namespace, path in args.location}

    # parse the first file to determine the schema and add locations
    if args.schema is None:
        assert len(args.file) > 0  # argparse should guarantee this
        path = find_file(args.file[0], args.include)
        if path is not None:
            logger.info('parsing %s (first file)' % path)
            root = ElementTree.parse(path).getroot()
            namespace = re.sub(r'^{(.+)}.+$', r'\1', root.tag)
            items = root.attrib.get(
                    '{http://www.w3.org/2001/XMLSchema-instance}'
                    'schemaLocation', '').strip().split()
            schema_location = dict(zip(items[0::2], items[1::2]))
            if namespace in schema_location:
                args.schema = schema_location[namespace]
                del schema_location[namespace]
                logger.info('set schema to %s' % args.schema)

            for namespace, file in schema_location.items():
                path = find_file(file, includes=args.include)
                if path is not None and namespace not in args.location:
                    # XXX use an absolute path; xmlschema doesn't work
                    #     reliably with relative paths (not sure why)
                    path = os.path.abspath(path)
                    args.location[namespace] = path
                    logger.info('set location %s to %s' % (namespace, path))

    # parse the schema to determine its minimum version
    schema_resource = None
    if args.schema is not None:
        path = find_file(args.schema, args.include)
        if path is not None:
            logger.info('parsing %s' % path)
            schema_resource = xmlschema.XMLResource(path, lazy=args.lazy,
                                                    defuse=args.defuse)
            min_version = schema_resource.root.attrib.get(
                    '{http://www.w3.org/2007/XMLSchema-versioning}minVersion',
                    None)

            # use this to set the version
            if args.version is None and min_version is not None:
                args.version = min_version
                logger.info('set schema version to %s' % args.version)

    # select the appropriate schema class
    schema_class = xmlschema.XMLSchema11 if args.version == '1.1' else \
        xmlschema.XMLSchema

    # use the schema imports to add locations (this is unlikely to add any new
    # ones)
    if schema_resource is not None:
        for import_ in schema_resource.root.findall(
                '{http://www.w3.org/2001/XMLSchema}import'):
            namespace = import_.attrib.get('namespace', '')
            schema_location = import_.attrib.get('schemaLocation', '')
            if namespace and schema_location:
                path = find_file(schema_location, includes=args.include)
                if path is not None and namespace not in args.location:
                    args.location[namespace] = path
                    logger.info('set location %s = %s' % (namespace, path))

    # load the schema
    # XXX this is for efficiency when validating multiple files, but it does
    #     assume that all of the XML files use the same schema
    schema = None
    if schema_resource is not None:
        logger.info('loading %s' % args.schema)
        try:
            schema = schema_class(schema_resource, locations=args.location,
                                  defuse=args.defuse, loglevel=loglevel)
            logger.info('loaded %s' % args.schema)
        except xmlschema.XMLSchemaParseError as error:
            logger.error(error.message)
        except xmlschema.XMLSchemaImportWarning as error:
            logger.error(error)

    # create a reverse namespace map: '{NAMESPACE}' -> 'PREFIX:' to use when
    # reporting XML elements and attributes
    namespaces = {}
    if schema is not None:
        namespaces = {f'{{{ns}}}': f'{pfx}:' for pfx, ns in
                      schema.namespaces.items()}

    # validate the files
    # XXX the first file may be parsed twice; could avoid this...
    tot_errors = 0
    ign_errors = 0
    for file in args.file:
        path = find_file(file, args.include)
        if path is not None:
            num_errors = 0
            path_or_tree = path
            if using_lxml:
                logger.info('parsing %s' % path)
                path_or_tree = ElementTree.parse(path)
            try:
                logger.info('validating %s' % path)
                for error in xmlschema.iter_errors(
                        path_or_tree, schema, schema_class,
                        locations=args.location, lazy=args.lazy):
                    if report_error(file, error, namespaces=namespaces,
                                    terse=args.terse):
                        num_errors += 1
                    else:
                        ign_errors += 1

            # XXX I'm not sure when this exception gets raised
            except (xmlschema.XMLSchemaException,
                    urllib.error.URLError) as error:
                if report_error(file, error, namespaces=namespaces,
                                terse=args.terse):
                    num_errors += 1
                else:
                    ign_errors += 1
                continue

            tot_errors += num_errors

    # exit status is the total number of errors
    logger.debug('%d errors (ignored %d)' % (tot_errors, ign_errors))
    return tot_errors


if __name__ == "__main__":
    sys.exit(main())
