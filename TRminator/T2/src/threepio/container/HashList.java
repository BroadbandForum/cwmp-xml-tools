/*
 * File: HashList.java
 * Project: Threepio
 * Author: Jeff Houle
 */

package threepio.container;

import java.util.ArrayList;
import java.util.HashMap;

/**
 * A HashList is a HashMap where the values are parameterized ArrayLists.
 * @param <K> - the key Type
 * @param <V> - the value Type that lists contain.
 * @see HashMap
 * @author jhoule
 */
public class HashList<K,V> extends HashMap<K, ArrayList<V>> {

    /**
     * Exposes the add function of ArrayList.
     * If there is no ArrayList for the Key, a list is created prior to the add.
     * @param k - the K to use as a key
     * @param v - the V to place in the list for the K.
     * @return the result of an ArrayList.add on that key.
     */
    public boolean put(K k, V v)
    {
        if (! this.containsKey(k))
        {
            this.put(k, new ArrayList<V>());
        }

        return this.get(k).add(v);
    }


     /**
     * Makes new entry for key, replacing old list if present.
     * puts the value on the top of the new list.
     * @param type - the key
     * @param value = the value
     */
    public void set(K type, V value)
    {
        ArrayList<V> temp = new ArrayList<V>();
        temp.add(value);
        // add new entry

        put(type, temp);
    }

}
