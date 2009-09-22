/*
 * File: ExclusiveVersionList.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.engine;

import threepio.container.Versioned;
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
        if (o instanceof Versioned)
        {
            Versioned it = (Versioned) o;

            int i;
            for (i = 0; (i < size() && !(get(i).getVersion().equals(it.getVersion()))); i++);

            return (i < size());
        }

        return super.contains(o);
    }
}
