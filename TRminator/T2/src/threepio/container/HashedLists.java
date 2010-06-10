/*
 * File: HashedLists.java
 * Project: Threepio
 * Author: Jeff Houle
 */

package threepio.container;

import java.util.ArrayList;
import java.util.HashMap;

/**
 * A HashedLists is a HashMap where the values are parameterized ArrayLists, and the keys are Strings.
 * @param <K> - the key Type
 * @param <V> - the value Type that lists contain.
 * @see HashMap
 * @author jhoule
 */
public class HashedLists<K, V> extends HashMap<K, ArrayList<V>> {

    /**
     * Exposes the add function of ArrayList.
     * If there is no ArrayList for the Key, a list is created prior to the add.
     * @param k - the K to use as a key
     * @param v - the V to place in the list for the K.
     * @return the result of an ArrayList.add on that key.
     */
    public boolean putOnList(K k, V v)
    {

        // TODO: resolve issue where type V is equal to ArrayList<V>.
        // that is, if V is ArrayList<Object>, and we try to putOnList an ArrayList<Object>,
        // it MAY overwrite the list for that key, rather than add to the list.

        if (! this.containsKey(k))
        {
            super.put(k, new ArrayList<V>());
        }

        return this.get(k).add(v);
    }


     /**
     * Makes new entry for key, replacing old list if present.
     * puts the value on the top of the new list.
     * @param key - the key
     * @param value = the value
     */
    public void set(K key, V value)
    {
        ArrayList<V> temp = new ArrayList<V>();
        temp.add(value);
        // add new entry

        super.put(key, temp);
    }

    /**
     * returns the indexth item in the list for the key.
     * @param key - the key to search for
     * @param index - the index of the list to return.
     * @return the indexth item in the list for the key,
     * null if the key isn't in the map, or the list is not big enough.
     */
    public V get(K key, int index)
    {
        ArrayList<V> temp = this.get(key);

        if (temp == null)
        {
            return null;
        }

        if (temp.size() >= index)
        {
            return null;
        }

        return temp.get(index);
    }

    /**
     * replaces the list of values for a key.
     * Use carefully!
     * @param key - the key to setList the list for.
     * @param value - the new list for that key.
     * @return the previous list for the key, null if there was none.
     */
    @SuppressWarnings("unchecked")
    public ArrayList<V> setList(K key, ArrayList value)
    {
        return super.put(key, value);
    }

    @Override
    public ArrayList<V> put(K k, ArrayList<V> value)
    {
        throw new UnsupportedOperationException("the put function is blocked in " +
                "order to protect the integrity of the underlying data structure. Use \"setList\" if you really want to do this.");
    }

}
