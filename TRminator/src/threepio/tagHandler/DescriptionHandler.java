/*
 * File: DescriptionHandler.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tagHandler;

import threepio.documenter.Doc;
import threepio.documenter.XTag;
import threepio.tabler.container.IndexedHashMap;
import threepio.tabler.container.Row;

/**
 * DescriptionHandler handles descriptions for the Tabler,
 * converting multiple tags and strings into a string that the tabler can put
 * in the description cell.
 *
 * @author jhoule
 */
public class DescriptionHandler extends TagHandler
{
    @Override
    public void handle(Doc doc, Doc before, XTag tag, IndexedHashMap columns, Row row, int where)
    {
        String s;
        boolean append = false;

        s = handle(doc, tag, append);

        row.set(where, s, append);
    }

    /**
     * a handle method with only the required arguments.
     * @param doc - the document being handled
     * @param tag - the tag that initated the description
     * @param flag - a boolean that
     * @return the string of what should be in a description section
     */
    public String handle(Doc doc, XTag tag, boolean flag)
    {
        // get description tag
        XTag t = tag;
        String s = null;
        StringBuffer buff = new StringBuffer();
        Object o;

        String action = t.getParams().get("action");

        if (action != null)
        {
            if (!action.equals("replace"))
            {
                flag = true;
            }
        }

        o = doc.poll();

        buff.append((String) o);
        o = doc.poll();
        while (!( o instanceof XTag) || (o instanceof  XTag && !(((XTag)o ).getType().equalsIgnoreCase("description"))))
        {
           s = o.toString();

           buff.append(s);
           o = doc.poll();
        }

        return buff.toString();
    }

    @Override
    public String getTypeHandled()
    {
        return "description";
    }
}
