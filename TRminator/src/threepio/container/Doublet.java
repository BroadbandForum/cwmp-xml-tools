/*
 * File: Doublet.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.container;

import java.util.Map.Entry;

/**
 * Doublet is a simple implementation of an Entry from a map,
 * for use elsewhere than a map.
 * Unlike an entry in a map, the key can be changed.
 *
 * @see java.util.Map.Entry
 * @param <K> - a key Type
 * @param <V> - a value Type
 * @author jhoule
 */
public class Doublet<K, V> implements Entry<K, V>
{

    K key;
    V val;

    /**
     * Empty consttructor.
     */
    public Doublet()
    {
        key = null;
        val = null;
    }

    /**
     * Set constructor. Key and value are set during construction.
     * @param key - the key for the entry
     * @param value - the value for the entry.
     */
    public Doublet(K key, V value)
    {
        this.key = key;
        val = value;
    }

    /**
     * copy constructor
     * @param orig - original Doublet<K, V> or Entry<K, V>
     */
    public Doublet(Entry<K, V> orig)
    {
        key = orig.getKey();
        val = orig.getValue();
    }

    @Override
    public K getKey()
    {
        return key;
    }

    @Override
    public V getValue()
    {
        return val;
    }

    @Override
    public V setValue(V value)
    {
        V temp = val;

        val = value;

        return temp;
    }

    /**
     * setKey works just like setValue, but sets the key instead of the value.
     * Because these Entries are not intended for actual Maps, the key can
     * be changed.
     * @param key - the new Key for the entry.
     * @return the old key.
     */
    public K setKey(K key)
    {
        K temp = this.key;

        this.key = key;

        return temp;
    }
}
