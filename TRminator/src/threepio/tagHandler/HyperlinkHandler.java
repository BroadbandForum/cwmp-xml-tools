/*
 * File: HyperlinkHandler.java
 * Project: Threepio
 * Author: Jeff Houle
 */

package threepio.tagHandler;

import threepio.documenter.Doc;
import threepio.documenter.XTag;
import threepio.tabler.container.IndexedHashMap;
import threepio.tabler.container.Row;

/**
 * HyperlinkHandler processes "hyperlink" tags.
 * @author jhoule
 */
public class HyperlinkHandler extends TagHandler{

    @Override
    public String getTypeHandled()
    {
       return "hyperlink";
    }

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
              System.err.println(getTypeHandled() + "was not String.");
        else
            row.set(where, "<a href = \"" + s + "\">" + s + "</a>");
    }
}
