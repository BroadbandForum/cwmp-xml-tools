/*
 * File: IndexedHashMap.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tabler.container;

import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;
import java.util.Map.Entry;

/**
 * IndexedHashMap is a hybrid class.
 * Publically, it is an arraylist of Entries.
 * The difference is that it has some hash map capabilites, due to it's
 * private map.
 * 
 * @author jhoule
 * @param <K> - the Type of the Keys in the Map.
 * @param <V> - the Type of the Values in the map.
 */
public class IndexedHashMap<K, V> extends ArrayList<Entry<K, V>>
{

    HashMap<K, V> map;

    /**
     * no-argument constructor,
     * instantiates the internal map.
     */
    public IndexedHashMap()
    {
        map = new HashMap<K, V>();
    }

    /**
     * adds an entry to the map and list.
     * @param ent - the entry to put on.
     */
    public void put(Entry<K, V> ent)
    {
        put(ent.getKey(), ent.getValue());
    }

    /**
     * puts a new entry in the list and map.
     * @param key - the key
     * @param value - the value for the key.
     * @return the old Value for this key.
     */
    public V put(K key, V value)
    {
        boolean found = false;
        boolean had = map.containsKey(key);

        // do normal put to map
        V oldval = map.put(key, value);

        if (!had)
        {
            // then find the entry in the map, and put it on the top-level list.
            Iterator<Entry<K, V>> it = map.entrySet().iterator();
            while (it.hasNext() && !found)
            {
                Entry<K, V> e = it.next();

                if (e.getKey().equals(key))
                {
                    super.add(e);
                    found = true;
                }
            }
        }

        return oldval;
    }

    /**
     * puts a new entry in the list and map, with the list's insertion being
     * at the specified location.
     * @param loc - where it goes in the list.
     * @param key - the key for the new entry.
     * @param value - the value for the new entry.
     * @return the old value, if there was one. null if not.
     */
    public V put(int loc, K key, V value)
    {
        boolean found = false;

        // do normal put to map
        V oldval = map.put(key, value);

        // then find the entry in the map, and put it on the top-level list.
        Iterator<Entry<K, V>> it = map.entrySet().iterator();
        while (it.hasNext() && !found)
        {
            Entry<K,V> e = it.next();

            if (e.getKey().equals(key))
            {
                super.add(loc, e);
                found = true;
            }
        }

        return oldval;
    }

    /**
     * puts a new entry in the list and map, with the list's insertion being
     * at the specified location.
     * @param loc - the location of where
     * @param ent - the entry
     * @return the old value for the key used.
     */
    public V put(int loc, Entry<K, V> ent)
    {
        return put(loc, ent.getKey(), ent.getValue());
    }

    /**
     * Returns the value for that key frmo the hash map, or null if there isn't one.
     * @param key - the key to get the value from.
     * @return the value.
     */
    public V get(K key)
    {
        return map.get(key);
    }

    /**
     * overridden to prevent adding to the list but not the map.
     * @param index
     * @param element
     */
    @Override
    public void add(int index, Entry<K, V> element)
    {
        throw new UnsupportedOperationException("no adding");
    }

    /**
     * puts all of m's items in the map.
     * @param m - the map to copy from.
     */
    public void putaAll(Map<? extends K, ? extends V> m)
    {
        map.putAll(m);

        Iterator<Entry<K, V>> it = map.entrySet().iterator();

        while (it.hasNext())
        {
            super.add(it.next());
        }
    }

    /**
     * puts all the entries from another IndexedHashMap
     * @param ihm
     */
    @SuppressWarnings("unchecked")
    public void putAll(IndexedHashMap ihm)
    {
        map.putAll(ihm.map);

        Iterator<Entry<K, V>> it = ihm.map.entrySet().iterator();
        while (it.hasNext())
        {
            super.add(it.next());
        }
    }

    /**
     * returns output from map's containsKey(K key)
     * @param key - the key to look for
     * @return true iff the key exists, false iff not.
     */
    public boolean containsKey(K key)
    {
        return map.containsKey(key);
    }

    /**
     * returns output from map's containsValue(V value))
     * @param value - the value to look for
     * @return true iff the value exists, false iff not.
     */
    public boolean containsValue(V value)
    {
        return map.containsValue(value);
    }

    /**
     * Removes the item with key theKey from the list and map.
     * @param theKey - the key of the thing to remove.
     * @return true if it was there.
     */
    public V removeByKey(K theKey)
    {
        int d = indexByKeyOf(theKey);

        if (d == -1)
        {
            return null;
        }

        this.remove(d);
        return map.remove(theKey);
    }

    /**
     * returns the index of an item by Key, -1 if not found.
     * @param theKey - the key of the thing to find.
     * @return the index, -1 if not found.
     */
    @SuppressWarnings("empty-statement")
    public int indexByKeyOf(K theKey)
    {
        int i;

        if (theKey == null)
            return -1;

        for (i = 0; i < this.size() && !this.get(i).getKey().equals(theKey); i++);

        if (i == this.size())
        {
            i = -1;
        }

        return i;
    }

    /**
     * returns the index of a value.
     * @param theVal - the value to search for.
     * @return the index of the value, -1 if not found.
     */
    @SuppressWarnings("empty-statement")
    public int indexByValOf(V theVal)
    {
        int i;
        for (i = 0; i < this.size() && !this.get(i).getValue().equals(theVal); i++);

        if (i == this.size())
        {
            i = -1;
        }

        return i;
    }

    /**
     * overridden to keep anything from adding to the list and missing the map.
     * @param e
     * @return nothing (always throws exception)
     */
    @Override
    public boolean add(Entry<K, V> e)
    {
        throw new UnsupportedOperationException("no adding");
    }

    /**
     * overridden to keep anything from adding to the list and missing the map.
     * @param index
     * @param c
     * @return nothing (alwasys throws exception)
     */
    @Override
    public boolean addAll(int index, Collection<? extends Entry<K, V>> c)
    {
        throw new UnsupportedOperationException("no adding at index");
    }

    /**
     * overridden to keep anything from adding to the list and missing the map.
     * @param c
     * @return true if anything was changed, false if not.
     */
    @Override
    public boolean addAll(Collection<? extends Entry<K, V>> c)
    {
        Iterator<? extends Entry<K, V>> it = c.iterator();

        boolean changed = false;

        while (it.hasNext())
        {
            put(it.next());
            changed = true;
        }

        return changed;
    }

    /**
     * overridden to keep anything from being removed from the list and missing the map.
     * @param o
     * @return nothing (always throws exception)
     */
    @Override
    public boolean remove(Object o)
    {
        throw new UnsupportedOperationException("no blind removal");
    }

    /**
     * overridden to keep anything from being removed from the list and missing the map.
     * @param index
     * @return true if something was removed, false if not there.
     */
    @Override
    public Entry<K, V> remove(int index)
    {
        Entry<K, V> temp = this.get(index);

        map.remove(temp.getKey());

        return super.remove(index);
    }

    /**
     * overridden to keep anything from being removed from the list and missing the map.
     * @param c
     * @return nothing (always throws exception)
     */
    @Override
    public boolean removeAll(Collection<?> c)
    {
        throw new UnsupportedOperationException("no blind removal");
    }

    /**
     * overridden to keep anything from being removed from the list and missing the map.
     * @param fromIndex
     * @param toIndex
     */
    @Override
    protected void removeRange(int fromIndex, int toIndex)
    {

        throw new UnsupportedOperationException("no blind removal");
    }

    /**
     * returns an array of the keys in the map.
     * @return the keys, as an array.
     */
    public Object[] toKeyArray()
    {
        Object[] keys = new Object[this.size()];
        for (int i = 0; i < this.size(); i++)
        {
            keys[i] = this.get(i).getKey();
        }

        return keys;
    }

    /**
     * swaps an entry's location with another's. returns true if the swap worked.
     * @param from - the loc of the first entry to swap
     * @param to - the loc of the other entry to swap.
     * @return true if the swap worked, false if not.
     */
    public boolean swap(int from, int to)
    {
        int end = this.size() - 1;

        if (!((from < 0 || from > end) || (to < 0 || to > end)))
        {
            Entry<K, V> temp = this.get(from);

            this.set(from, this.get(to));
            this.set(to, temp);

            return true;
        }
        return false;
    }

    /**
     * moves an Entry in the list from one index to another.
     * @param from - the old index
     * @param to - the new index
     * @return true if the move was done, false if not.
     */
    public boolean move(int from, int to)
    {
        int end = this.size() -1;


         if (!((from < 0 || from > end) || (to < 0 || to > end)))
        {
            Entry<K, V> temp = this.get(from);

            this.remove(from);
            this.put(to, temp);

            return true;
        }
        return false;

    }

    /**
     * clear clears the map and list of all entries.
     */
    @Override
    public void clear()
    {
        map.clear();

        super.clear();
    }
}
