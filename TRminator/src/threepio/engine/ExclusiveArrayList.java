/*
 * File: ExclusiveArrayList.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.engine;

import java.util.ArrayList;

/**
 * ExclsuiveArrayList is an arraylist that doesn't accept having more than one
 * item with the same value in it.
 * @see ArrayList
 * @author jhoule
 * @param <K> - a Key type.
 */
public class ExclusiveArrayList<K> extends ArrayList<K>
{
    // optional name
    String name;


    /**
     * sets the OPTIONAL name for this list.
     * @param n - the name to set.
     */
    public void setName(String n)
    {
        name = n;
    }

  /**
   * gets the OPTIONAL name for this list.
   * @return the name, null if not set.
   */
    public String getName()
    {
        return name;
    }

    /**
     * Adding overridden to only accept one instance of a K
     * @param e - the K to try to add.
     * @return true if it was added, false if it was already there.
     */
    @Override
    public boolean add(K e)
    {
        if (contains(e))
        {
            return false;
        }

        return super.add(e);
    }

     /**
     * Adding overridden to only accept one instance of a K
     * @param element - the K to try to add.
     */
    @Override
    public void add(int index, K element)
    {
        if (!contains(element))
        {
            super.add(index, element);
        }

    }

    /**
     * Returns each item on the list, each on a new line, as a string.
     * @return the items listed, as a String.
     */
    @Override
    public String toString()
    {
        StringBuffer buff = new StringBuffer();

       for (int i = 0; i < this.size(); i++)
       {
           buff.append(this.get(i));
           buff.append("\n");
       }

        return buff.toString();
    }

    /**
     * Adds another list to this one.
     * Rules still apply. If the list contains an item already in this list,
     * it is omitted.
     * @param other - the other list.
     */
    public void add(ArrayList<K> other)
    {
       for (int i = 0; i < other.size(); i++)
       {
           this.add(other.get(i));
       }
    }
}
