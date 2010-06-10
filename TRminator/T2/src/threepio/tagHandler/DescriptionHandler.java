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

    private IndexedHashMap<String, String> theHiddens()
        {
            IndexedHashMap<String, String> map = new IndexedHashMap<String, String>();

           
            map.put("string", "an empty string");
            map.put("boolean", "false");
            map.put("list", "an empty list");
            

            return map;
        }

    @Override
    public void handle(Doc doc, Doc before, XTag tag, IndexedHashMap columns, Row row, int where)
    {
        String s, t ;
        Object o;
        Boolean append = false, hid = false;

        s = handle(doc, tag, append);

        o = row.getBucket().get("hidden");

        if (o != null)
        {

            hid = (Boolean) o;

            if (hid)
            {
                s += ("\n\nThis value is HIDDEN and will ALWAYS return <i>");

                o = row.getBucket().get("type");

                if (o == null)
                {
                    t = "nothing";
                }
                else
                {
                    t = theHiddens().get((String)o);

                    if (t == null)
                    {
                        t = "nothing";
                    }
                }

                s += t + "</i> when read, regardless of the actual value.";
            }
        }


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

        String action = t.getAttributes().get("action");

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
        while (!(o instanceof XTag) || (o instanceof XTag && !(((XTag) o).getType().equalsIgnoreCase("description"))))
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

    @Override
    public String getFriendlyName()
    {
        return "Description";
    }
}
