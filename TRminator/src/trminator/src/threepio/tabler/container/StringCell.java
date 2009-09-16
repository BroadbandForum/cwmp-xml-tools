/*
 * File: StringCell.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tabler.container;

/**
 * StringCell is an extension that provides shortcuts to string operations.
 * @author jhoule
 */
public class StringCell extends Cell<String>
{

    /**
     * Standard constructor
     * @param e - the element to put inside.
     */
    StringCell(String e)
    {
        super(e);
    }

    /**
     * performs a String.equalsIgnoreCase on the data in this cell and the given string.
     * @param e - the other string.
     * @return true if they are equal, false if not.
     */
    public boolean equals(String e)
    {
        return this.data.equalsIgnoreCase(e);
    }

    public void prePend(String e)
    {
        if (this.data == null)
        {
            set(e, this.getFlag());
        } else
        {
            this.data = e + this.data;
        }
    }

    /**
     * performs a String.contains on the data in this cell and the given string.
     * @param e - the other string.
     * @return true if the string is contained here, false if not.
     */
    boolean contains(String e)
    {
        return (this.data.contains(e) || this.data.contains(e.toLowerCase()) || this.data.contains(e.toUpperCase()));
    }
}
