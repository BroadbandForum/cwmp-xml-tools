/*
 * File: MultiMap.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.printer.container;

import java.util.HashMap;
import java.util.LinkedList;

/**
 * A MultiMap is a hashmap with Strings as Keys and generic Linked Lists for values.
 * Some functionality has been added, exposing the lists.
 * @author jhoule
 */
public abstract class MultiMap<E> extends HashMap<String, LinkedList<E>>
{

    /**
     * shortcut to containsKey
     * @param t - a string to search for
     * @return true if the key t is on the map, false if not.
     */
    public boolean contains(String t)
    {
        return this.containsKey(t);
    }

    /**
     * adds the value to the list associated with the key,
     * makes new entry if none existed.
     * @param type - the key
     * @param value - the value
     */
    public void add(String type, E value)
    {

        if (contains(type))
        {
            // type already existed. change value for entry..
            this.get(type).add(value);
        } else
        {

            set(type, value);
        }
    }

    @Override
    public LinkedList<E> put(String key, LinkedList<E> value)
    {
        return super.put(key, value);
    }

    /**
     * Makes new entry for key, replacing old list if present.
     * puts the value on the top of the new list.
     * @param type - the key
     * @param value = the value
     */
    public void set(String type, E value)
    {
        LinkedList<E> temp = new LinkedList<E>();
        temp.add(value);
        // add new entry

        put(type, temp);
    }
}
