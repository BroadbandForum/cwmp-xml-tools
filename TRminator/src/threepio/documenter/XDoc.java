/*
 * File: XDoc.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.documenter;

import threepio.container.Doublet;
import java.util.Collection;
import java.util.Iterator;

/**
 * The XDoc is a Doc that only accepts XTags and java Strings.
 * As Docs are versioned,
 * @author jhoule
 */
public class XDoc extends Doc
{

    /**
     * no-argument constructor
     */
    public XDoc()
    {
        super();
    }

    /**
     * copy constructor
     * @param other - another XDoc
     */
    public XDoc(XDoc other)
    {
        super(other);
    }

    /**
     * returns a copy of this XDoc.
     * @return the copy
     */
    @Override
    public XDoc copyOf()
    {
        XDoc two = new XDoc();

        two.addAll(this);

        two.setVersion(this.version);

        return two;
    }

    /**
     * Overrides the default add, to keep random objects from getting thrown in.
     * @param o - an Object to add.
     * @return <tt>true</tt>
     */
    @Override
    public boolean add(Object o)
    {
        if (o instanceof XTag)
        {
            return offer((XTag) o);
        }

        if (o instanceof String)
        {
            return offer((String) o);
        }

        throw new UnsupportedOperationException("That object type is Not supported");
    }

    /**
     * overridden to yell at anyone adding anything other than an XTag or String
     * @param c - the collection to add from.
     * @return true if anything was changed, false if not.
     */
    @Override
    public boolean addAll(Collection c)
    {
        Object o;

        if (c == null)
        {
            throw new NullPointerException();
        }
        if (c == this)
        {
            throw new IllegalArgumentException();
        }
        boolean modified = false;
        Iterator e = c.iterator();
        while (e.hasNext())
        {
            o = e.next();
            if (!((o instanceof XTag) || (o instanceof String)))
            {
                throw new UnsupportedOperationException("That object type is Not supported");
            }

            if (add(o))
            {
                modified = true;
            }
        }
        return modified;
    }

    /**
     * runs over everything in the document, up the first tag of given type.
     * WARNING: modifies the Doc.
     * @param type - the type of tag to go up to.
     * @return an Entry with a key that is the stuff after the area run over, and a value of the parts that were run over.
     */
    public Doublet<XDoc, XDoc> runOver(String type)
    {
        Object x;
        XDoc trash = new XDoc();

        x = peek();
        // skip past parts that aren't import tags
        while (x != null &&
                ((!(x instanceof XTag)) ||
                ((x instanceof XTag) && (!(((XTag) x).getType().equals(type))))))
        {
            trash.add(poll());
            x = peek();
        }

        // now should be at next tag of type.
        // COULD BE A CLOSER.
        return new Doublet(this, trash);
    }

    /**
     * returns a new document, which is this one, less the items prior
     * to the first tag of given type.
     * WARNING: modifies the Doc.
     * @see #runOver(java.lang.String)
     * @param type - the type to purge up to.
     * @return the new document.
     */
    public XDoc purgeToTag(String type)
    {
        return runOver(type).getKey();
    }

    /**
     * returns a new document filled with what was "thrown out" 
     * while purging to a tag as described in passed values.
     * WARNING: modifies the Doc.
     * @param type - the type of tag.
     * @param closer - whether the tag is a closing tag or not.
     * @return the new document.
     */
    public XDoc getTheTrash(String type, boolean closer)
    {
        return runOver(type).getValue();
    }

    @Override
    public String toString()
    {
        return super.toString();
    }

    
}
