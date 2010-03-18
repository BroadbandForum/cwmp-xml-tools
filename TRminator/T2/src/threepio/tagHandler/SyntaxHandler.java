/*
 * File: SyntaxHandler.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tagHandler;

import java.util.HashMap;
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
    public void handle(Doc doc, Doc before, XTag tag, IndexedHashMap<String, String> columns, Row row, int where)
    {
        XTag t = null, temp;
        boolean lo = false, hi = false;
        String value = null;
        int sz = -1, szTwo = -1;
        String intString = null, type = null, tmp = null;
        boolean findDefault = false;
        Object x;
        int descr = columns.indexByValOf("description");
        HashMap<String, String> params;

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

        value = t.getType();

        // handle the fact that some syntax tags have a "/" at the end.
        if (value.contains("/"))
        {
            value = value.replace('/', ' ');
        }

        value = value.trim();

        temp = (XTag) doc.peek();
        params = temp.getParams();

        if (value.equals("string") && temp != null)
        {
            intString = params.get("maxLength");

            if (intString != null)
            {
                sz = Integer.parseInt(intString);
                value = (value + "(" + sz + ")");

            }

            // String without maxLength is just String. No mod needed.

        }

        if (value.equals("unsignedint") && temp != null)
        {
            intString = params.get("minInclusive");

            if (intString != null)
            {
                lo = true;
                sz = Integer.parseInt(intString);
            }

            intString = params.get("maxInclusive");

            if (intString != null)
            {
                hi = true;
                szTwo = Integer.parseInt(intString);
            }

            if (lo && hi)
            {
                value = (value + "[" + sz + ", " + szTwo + "]");
            }
        }

        if (value == null || value.isEmpty())
        {

            value = Table.BLANK_CELL_TEXT;
        }

        // so put that in the row for this.
        row.set(where, value);

        // check for a need to find default.
        where = columns.indexByValOf("DEFAULT");

        if (where >= 0)
        {
            findDefault = true;
        }

        // pop upto and </syntax>
        while ((!(doc.peek() instanceof XTag)) || (doc.peek() instanceof XTag && !((XTag) doc.peek()).getType().equals(getTypeHandled())))
        {
            x = doc.poll();
            tmp = null;

            if (x instanceof XTag)
            {
                t = ((XTag) x);
                params = t.getParams();
                type = t.getType();
                value = "";

                if (!t.isCloser())
                {
                    if (findDefault && type.equals("default"))
                    {
                        tmp = params.get("value");

                        if (tmp != null)
                        {
                            value = tmp;

                            if (value == null)
                            {
                                System.err.println(params.containsKey("value"));
                            }
                        }

                        status = params.get("status");


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

                    }

                    if (type.equalsIgnoreCase("enumeration"))
                    {
                        row.addToBucket(new BBFEnum(t));
                    }
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

     @Override
    public String getFriendlyName()
    {
        return "Type";
    }
}
