/*
 * File: SyntaxHandler.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tagHandler;

import threepio.documenter.Doc;
import threepio.documenter.XTag;

import threepio.tabler.BBFEnum;
import threepio.tabler.container.IndexedHashMap;
import threepio.tabler.container.Row;
import threepio.tabler.container.Table;

/**
 * SyntaxHandler is a TagHandler for "syntax".
 * @author jhoule
 */
public class SyntaxHandler extends TagHandler
{

    @Override
    public void handle(Doc doc, Doc before, XTag tag, IndexedHashMap columns, Row row, int where)
    {
        XTag t = null;
        String value = null;
        int sz = -1;
        String intString = null, type = null;
        boolean findDefault = false;
        Object x;
        int descr = columns.indexByValOf("description");

        String status = null;

        // ignore first tag, passed to method, since that would be <syntax>.

        // pop next thing, should be t
        Object o = doc.poll();

        try
        {
            t = (XTag) o;
        } catch (Exception ex)
        {
            System.err.println("Syntax was not tag.");
        }

        value = t.getType().toLowerCase();

        // handle the fact that some syntax tags have a "/" at the end.
        if (value.contains("/"))
        {
            value = value.replace('/', ' ');
        }

        value = value.trim();

        if (value.equals("string"))
        {
            intString = t.getParams().get("maxLength");

            if (intString != null)
            {
                sz = Integer.parseInt(t.getParams().get("maxLength"));
                value = ("String(" + sz + ")");

            }

            // String without maxLength is just String. No mod needed.

        }
        // unsignedInt needs no modification

        if (value == null || value.isEmpty())
        {


            value = Table.BLANK_CELL_TEXT;
        }

        // so put that in the row for this.
        row.set(where, value);

        // check for a need to find default.
        where = columns.indexByValOf("default");

        if (where >= 0)
        {
            findDefault = true;
        }

        // pop upto and </syntax>
        while ((!(doc.peek() instanceof XTag)) || (doc.peek() instanceof XTag && !((XTag) doc.peek()).getType().equals("syntax")))
        {
            x = doc.poll();

            if (x instanceof XTag)
            {
                t = ((XTag) x);
                type = t.getType();

                if (findDefault && type.equals("default"))
                {
                    
                    if (t.getParams().containsKey("status"))
                    {
                        status = t.getParams().get("status");
                    }

                    if (t.getParams().containsKey("value"));
                    {
                        value = t.getParams().get("value");

                        // set the default
                        if (value.equals("1.0"))
                        {
                            status = t.getParams().get("status");
                        }

                        if (value.isEmpty() || value == null)
                        {
                            if (status == null || status.isEmpty())
                            {
                                value = Table.BLANK_CELL_TEXT;
                            } else
                            {
                                value = "STATUS = " + status;
                            }
                        }

                        row.set(where, value);

                        if (!(status == null || status.isEmpty()) && row.get(descr).getData().equals(Row.BLANK_CELL_TEXT))
                        {
                            row.set(descr, "STATUS = " + status);
                        }
                    }
                }

                if (type.equalsIgnoreCase("enumeration") && !t.isCloser())
                {
                    row.addToBucket(new BBFEnum(t));
                }
            }
        }

        doc.poll();
    }

    @Override
    public String getTypeHandled()
    {
        return "syntax";
    }
}
