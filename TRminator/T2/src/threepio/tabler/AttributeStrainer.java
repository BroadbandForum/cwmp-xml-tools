/*
 * File: AttributeStrainer.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tabler;

import java.util.HashMap;
import threepio.documenter.XTag;
import threepio.tabler.container.Row;
import threepio.tabler.container.Table;

/**
 * AttributeStrainer subjects a tag to "straining" of its attributes into
 *
 * @author jhoule
 */
public class AttributeStrainer
{
    static SingleAttributeHandler handlers[] =
    {
        new NumEntriesHandler()
    };

    public static void strain (XTag t, Table Table, String curRowName)
    {
        for (SingleAttributeHandler h: handlers)
        {
            h.handle(t, Table, curRowName);
        }
    }

}

/**
 * NumEntriesHandler gathers information from a tag's parameters
 * that has to do with "numEntriesParameter."
 * it sets the "numEntriesParameter" value for a Row in a Table.
 * @see Table
 * @see Row
 * @author jhoule
 */
class NumEntriesHandler extends SingleAttributeHandler
{

    final String toHandle = "numEntriesParameter";

    @Override
    public void handle(XTag t, Table table, String curRowName)
    {
        {
            Row otherRow = null;
            HashMap<String, String> attributes = null;
            String temp;


            // parse getAttributes from componentTag into row
            attributes = t.getAttributes();

            temp = attributes.get(toHandle);

            if (temp != null)
            {
                otherRow = table.get(temp);

                if (otherRow == null)
                {
                    // item isn't in the table yet.
                    // technically we shouldn't have to rely on this.

                    // if we are not guaranteed to have the numEntriesParameter prior to the parameter
                    // being counted, we should externally keep these links, instead.

                    System.err.println("count parameter is not present yet!");
                } else
                {
                    otherRow.getBucket().putOnList("numentries", curRowName);
                }
            }
        }
    }

    @Override
    public String handles()
    {
        return toHandle;
    }
}
