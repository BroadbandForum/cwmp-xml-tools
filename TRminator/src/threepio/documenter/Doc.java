/*
 * File: Doc.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.documenter;

import threepio.container.Versioned;
import java.util.Collection;
import java.util.Iterator;
import java.util.concurrent.ConcurrentLinkedQueue;

/**
 * Doc is an abstract extension of Queue, that is versioned and removes
 * case restrictions on contains(t) when t is a string.
 * Doc is currently currently serving as a super class for XDoc.
 * @see XDoc
 * @author jhoule
 */
public abstract class Doc extends ConcurrentLinkedQueue implements Versioned
{
    String version;
    String path;

    /**
     * empty constructor.
     */
    public Doc()
    {
        this.version = "";
    }

    /**
     * constructs a new document, using the original document to build up from.
     * @param orig
     */
    public Doc(Doc orig)
    {
        this();

        this.addAll(orig);

        this.version = orig.version;
    }

    /**
     * gets the path where the "real" document resides.
     * @return the path of the file for the Doc.
     */
    public String getPath()
    {
        return path;
    }

    /**
     * sets the path where the "real" document resides.
     * @param newPath - the new path of the file for the Doc.
     */
    public void setPath(String newPath)
    {
        path = newPath;
    }

    /**
     * Uses equalsIgnoreCase to check if the String is in the Doc.
     * @param str - the string to check for.
     * @return true if the string is in the Doc, false if not.
     */
    public boolean contains(String str)
    {
        Iterator it = this.iterator();

        Object o;

        while (it.hasNext())
        {
            o = it.next();

            if (o instanceof String && ((String) o).equalsIgnoreCase(str))
            {
                return true;
            }
        }

        return false;
    }

    /**
     * returns the presence of a tag of the type passed.
     * @param type - the type of tag checked for.
     * @return true if that kind of tag is in the Doc, false if not.
     */
    public boolean containsTagType(String type)
    {
        Iterator it = this.iterator();
        Object o;

        while (it.hasNext())
        {
            o = it.next();

            if (o instanceof XTag && ((XTag) o).getType().equalsIgnoreCase(type))
            {
                return true;
            }
        }

        return false;
    }

    /**
     * Returns a copy of this document, containing all of the same items
     * @return the copy.
     */
    public abstract Doc copyOf();

    @Override
    public String getVersion()
    {
        return version;
    }

    @Override
    public void setVersion(String v)
    {

        version = v;
    }

    /**
     * Child classes of Doc are to implement add separately, to ensure that the specific
     * rules for the class are followed.
     * @param o - the object being added.
     * @return the result of the addition.
     */
    @Override
    public abstract boolean add(Object o);

    /**
     * Child classes of Doc are to implement addAll separately, to ensure that the specific
     * rules for the class are followed.
     * @param c - the collection of objects being added.
     * @return the result of the addition.
     */
    @Override
    public abstract boolean addAll(Collection c);

    @Override
    public String toString()
    {
        StringBuilder builder = new StringBuilder();

        builder.append(this.getClass().getName());
        builder.append(" ");
        builder.append(this.version);
        builder.append(" size = ");
        builder.append(this.size());

        return builder.toString();
    }


}
