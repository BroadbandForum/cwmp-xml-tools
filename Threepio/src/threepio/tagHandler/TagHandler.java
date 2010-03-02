/*
 * File: TagHandler.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tagHandler;

import threepio.documenter.Doc;
import threepio.documenter.XTag;
import threepio.tabler.container.IndexedHashMap;
import threepio.tabler.container.Row;

/**
 * TagHandler is an abstract class with some common elements of classes for
 * handling XML tags.
 * @author jhoule
 */
public abstract class TagHandler
{

    /**
     * returns the string of the item type in the XML that this handler is for.
     * it is required to return a valid String for all TagHandlers in order to make
     * the HandlerFactory work correctly.
     * @return the type this handler handles.
     */
    public abstract String getTypeHandled();

    /**
     * returns the string that should be used when labeling the results of this
     * tag parser.
     * @return the "label" for the Tag's results.
     */
    public abstract String getFriendlyName();


    /**
     * handle (XDoc) handles the document, popping the parts it parses.
     * what is left of the document is what is after the closing tag of the part
     * the handler was to parse.
     * @param doc - the document to handle.
     * @param before - the parts of the document that occurred before the Tag.
     * @param tag - the tag to handle.
     * @param columns - a map of the columns required in a table.
     * @param row - the row where the tag to handle shows up.
     * @param where - the index of the cell in which to put the result of the handling of the tag.
     */
    public abstract void handle(Doc doc, Doc before, XTag tag, IndexedHashMap columns,
            Row row, int where);
}
