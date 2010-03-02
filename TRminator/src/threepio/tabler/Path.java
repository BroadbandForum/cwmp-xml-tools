/*
 * File: Path.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tabler;

import java.util.ArrayList;

/**
 * Path represents a path, where names are separated by a delimiter.
 * @author jhoule
 */
public class Path extends ArrayList<String> implements Comparable
{

    /**
     * the delimiter for the paths
     */
    public final static String delim = ".";
    /**
     * the name/ID to be used for the Root object of a path.
     */
    public final static String rootName = "ROOT";

    /**
     * Default constructor.
     */
    public Path()
    {
        super();
    }

    /**
     * Constructor.
     * initializes variables based on the path passed as a String.
     * @param s - a path to decompose, as a String.
     */
    public Path(String s)
    {
        int start = 0, end = -1;
        StringBuffer buffer = new StringBuffer(s);

        end = buffer.indexOf(delim);

        while (end > 0)
        {
            this.add(buffer.substring(start, end));

            buffer.delete(start, end + 1);
            end = buffer.indexOf(delim);
        }

        if (buffer.length() > 0)
        {
            this.add(buffer.toString());
        }

    }

    /**
     * determines if this path is a direct decendent of the path passed.s
     * @param p - another path
     * @return true iff this path is a direct child of p, false if not.
     */
    public boolean isDirectChildOf(Path p)
    {
        String one, two;

        one = this.removeI().toString();
        p.removeLast();

        two = p.toString();

        return (two.contains(one));
    }

    /**
     * determines if this path and another share a direct parent.
     * @param p - another path
     * @return true iff this path and p are children of the same direct parent, false if not.
     */
    public boolean isOnSameLevelAs(Path p)
    {
        Path a, b;

        a = this.removeI();
        a.removeLast();

        b = p.removeI();
        b.removeLast();

        return (a.compareTo(b) == 0);
    }

    /**
     * determines if this path is less deep than another.
     * @param p - another path.
     * @return true iff this path is shallower than p, false if not.
     */
    public boolean shallowerThan(Path p)
    {
        return this.compareTo(p) < 0;
    }

    /**
     * determines if this path is deeper than another.
     * @param p - another path
     * @return true iff this path is deeper than p, false if not.
     */
    public boolean deeperThan(Path p)
    {
        return this.compareTo(p) > 0;
    }

    @SuppressWarnings("empty-statement")
    @Override
    public int compareTo(Object o)
    {
        if (!(o instanceof Path))
        {
            throw new IllegalArgumentException("comparability not determinable between " + o.getClass().getName() + " and Path");
        }

        Path a, b, p;

        p = (Path) o;

        a = this.removeI();
        b = p.removeI();
        int i = 0;


        if (a.size() > b.size())
        {
            for (i = 0; (i < b.size() && a.get(i).equals(b.get(i))); i++);

            return a.size() - i;

        } else
        {
            for (i = 0; (i < a.size() && a.get(i).equals(b.get(i))); i++);

            return i - b.size();
        }
    }

    /**
     * removes the "ith" notation from the path.
     * this is commonly found with Array-type objects in BBF XML.
     * @return a Path that is this one, without the "ith" notation.
     */
    public Path removeI()
    {
        Path other;
        String str = this.toString(), iString = ".{i}";
        str = str.replace(iString, "");

        other = new Path(str);

        return other;
    }

    /**
     * overwritten to correctly re-form the path from this structure.
     * @return a string representation of this Path.
     */
    @Override
    public String toString()
    {
        StringBuffer buffer = new StringBuffer();
        for (int i = 0; i < this.size(); i++)
        {
            buffer.append(this.get(i));

            if (i + 1 < this.size())
            {
                buffer.append(delim);
            }
        }

        return buffer.toString();
    }

    /**
     * removes the last item from the Path.
     * @return a Path that is like this one, but does not have the last part.
     */
    public Path removeLast()
    {
        if (!this.isEmpty())
        {
            this.remove(this.size() - 1);
        }

        return this;
    }

    /**
     * returns the last part of the path, or <code>rootName</code> if there is no path.
     * @return the last part of the path, <code>rootName</code> if none.
     */
    public String getLastPart()
    {
        Path p;
        if (this.isEmpty())
        {
            return rootName;
        }

        p = this.removeI();

        return p.get(p.size() - 1);

    }

    /**
     * determines if this is the path of an Array-type object in BBF XML.
     * @return true iff the path is for an Array-type object, false iff not.
     */
    public boolean isArray()
    {
        return (!this.isEmpty() && this.get(this.size() - 1).equalsIgnoreCase("{i}"));
    }

}
