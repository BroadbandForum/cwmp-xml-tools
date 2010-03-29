/*
 * File: ColumnMap.java
 * Project: Threepio
 * Author: Jeff Houle
 */

package threepio.tabler.container;

/**
 * ColumnMap is an IndexedHashMap with keys and values of type String.
 * The index getter functions ignore case when searching.
 * @author jhoule
 * @see IndexedHashMap
 */
public class ColumnMap extends IndexedHashMap<String, String> {

    public ColumnMap()
    {
        super();
    }

    @Override
    @SuppressWarnings("empty-statement")
    public int indexByKeyOf(String theKey)
    {
         int i;

        if (theKey == null)
            return -1;

        for (i = 0; i < this.size() && !this.get(i).getKey().equalsIgnoreCase(theKey); i++);

        if (i == this.size())
        {
            i = -1;
        }

        return i;
    }

    @Override
    @SuppressWarnings("empty-statement")
    public int indexByValOf(String theVal)
    {
         int i;
        for (i = 0; i < this.size() && !this.get(i).getValue().equalsIgnoreCase(theVal); i++);

        if (i == this.size())
        {
            i = -1;
        }

        return i;
    }

    

}
