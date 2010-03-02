/*
 * File: GeneralTagHandler.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tagHandler;

import threepio.documenter.Doc;
import threepio.documenter.XTag;
import threepio.tabler.container.IndexedHashMap;
import threepio.tabler.container.Row;

/**
 * GeneralTagHandler is an abstract class that can be extended to handle tags like:
 * <thing> blah blah </thing>
 * @author jhoule
 */
public abstract class GeneralTagHandler extends TagHandler
{

    @Override
    public void handle(Doc doc, Doc before, XTag tag, IndexedHashMap columns, Row row, int where)
    {
        Object o = doc.poll();
        String s = null;

        try
        {
            s = (String) o;
        } catch (Exception ex)
        {
            System.err.println(getTypeHandled() + "was not String.");
        }

        // pop closer tag.
        doc.poll();

        if (s == null)
        {
            System.err.println(getTypeHandled() + "was not String.");
        } else
        {
            row.set(where, s);
        }
    }
}
