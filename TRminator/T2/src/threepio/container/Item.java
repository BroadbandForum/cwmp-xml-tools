/*
 * File: Item.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.container;

/**
 * An Item has a lebel/name and a HashedLists of parameters/properties.
 * @see HashedLists
 * @author jhoule
 */
public class Item
{

    String label;
    HashedLists<String, Object> params;

    /**
     * no-argument constructor
     * sets up the parameter map, and gives it a clear Label.
     */
    public Item()
    {
        label = "";
        params = new HashedLists<String, Object>();
    }

    /**
     * naming constructor.
     * sets up the parameter map, and gives the Item the specified Label.
     * @param l
     */
    public Item(String l)
    {
        label = l;
        params = new HashedLists<String, Object>();
    }

    /**
     * sets the label for the Item.
     * @param l - the String for the label.
     */
    public void setLabel(String l)
    {
        if (l == null)
        {
            label = "";
        }
        label = l;
    }

    /**
     * returns the label for this Item.
     * @return the Item's label. May be an empty string, but is never null.
     */
    public String getLabel()
    {
        return label;
    }

    /**
     * returns the parameters for this Item.
     * @return the HashedLists of parameters.
     */
    public HashedLists<String, Object> getParams()
    {
        return params;
    }
}
