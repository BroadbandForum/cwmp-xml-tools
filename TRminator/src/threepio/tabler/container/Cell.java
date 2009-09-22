/*
 * File: Cell.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tabler.container;

/**
 * A Cell is a cell of a table.
 * It is where the "live" parts of the table happen, such as "knowing" if the data
 * was changed, or was inserted.
 * @author jhoule
 */
public abstract class Cell<E>
{

    E data;
    boolean changed;
    boolean empty;
    boolean fresh;
    boolean special;

    /**
     * An empty constructor.
     * Initializes all status booleans.
     */
    public Cell()
    {
        changed = false;
        empty = true;
        fresh = true;
        special = false;
    }

    /**
     * A constructor that sets the cell's internal data.
     * All functions of empty constructor are also carried out.
     * @param it - the data to construct the cell with.
     */
    public Cell(E it)
    {
        this();
        data = it;
        empty = false;
    }

    /**
     * sets the data in the cell.
     * sets the flag to false.
     * @param it - the value to set data to.
     */
    public void set(E it)
    {
        set(it, false);
    }

    /**
     * Sets the data in the cell,
     * Also updates flags based on previous data and new data.
     * @param it - the value to set data to
     * @param flag - the value to set the flag to.
     */
    public void set(E it, boolean flag)
    {
        special = flag;
        if (data == null)
        {
            // we are constructing this cell
            data = it;
            fresh = true;
            changed = true;
        } else
        {
            // this cell has already been constructed
            fresh = false;
            empty = false;

            if (data.equals(it))
            {
                // the data's the same, so no change actually has taken place
                changed = false;
            } else
            {
                // the data is different, so update the contents, and change the flag.
                changed = true;
                data = it;
            }
        }
    }

    /**
     * Sets without modifying anything but the data.
     * USING THIS CAN BREAK THE "SELF-AWARE" PART OF CELLS.
     * This method is intended ONLY for "invisible" modifications, such as creating anchors and links.
     * @param it
     */
    public void silentSet(E it)
    {
        data = it;
    }

    /**
     * returns the changed state of the cell.
     * @return - the change state.
     */
    public boolean getChanged()
    {
        return changed;
    }

    /**
     * returns the freshness of the cell. If it was just constructed, it is fresh.
     * @return true if the cell hasn't been inserted with data, false if it has.
     */
    public boolean getFresh()
    {
        return fresh;
    }

    /**
     * makes the cell appear to not be changed nor fresh,
     * no matter what the previous state was.
     */
    public void makeStale()
    {
        fresh = false;
        changed = false;
    }

    /**
     * makes the cell fresh.
     */
    public void makeFresh()
    {
        fresh = true;

    }

    /**
     * Returns the object inside of the cell.
     * @return - the object.
     */
    public E getData()
    {
        return data;
    }

    /**
     * returns the value of teh special flag.
     * @return the special flag.
     */
    public boolean getFlag()
    {
        return special;
    }

}
