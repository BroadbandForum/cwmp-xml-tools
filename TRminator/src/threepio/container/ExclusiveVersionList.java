/*
 * File: ExclusiveVersionList.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.container;

import java.util.ArrayList;

/**
 * ExclsuiveArrayList is an arraylist that doesn't accept having more than one
 * copy of the same versioned object in it.
 * @see ArrayList
 * @see Versioned
 * @author jhoule
 * @param <K> - a Key Type that extends Versioned
 */
public class ExclusiveVersionList<K extends Versioned> extends ExclusiveArrayList<K>
{

    /**
     * overridden to do contains checks on versions, if present, instead of hashes.
     * @param o - the item to check for.
     * @return true if the K is inside the List, false if not.
     */
    @Override
    @SuppressWarnings("empty-statement")
    public boolean contains(Object o)
    {
        Versioned it = (Versioned) o;

        return ((find(it.getVersion())) >= 0);
    }

    public boolean containsVersion(String v)
    {
        return ((find(v)) >= 0);
    }

    @SuppressWarnings("empty-statement")
    public int find(String version)
    {
        int i;
        for (i = 0; (i < size() && !(get(i).getVersion().equals(version))); i++);

        if (i < size())
        {
            return i;
        }
        return -1;
    }

    public K get(String version)
    {
        int loc = find(version);

        if (loc >= 0)
        {
            return this.get(loc);
        }

        return null;
    }
}
