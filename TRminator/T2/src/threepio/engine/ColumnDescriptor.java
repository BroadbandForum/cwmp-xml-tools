/*
 * File: ColumnDescriptor.java
 * Project: Threepio
 * Author: Jeff Houle
 */

package threepio.engine;

import threepio.container.Doublet;

/**
 * A ColumnDescriptor is an Abstract Class for describing a Column.
 * It is usually extended by fairly complex classes that are related to Columns,
 * so that other classes know what parameter use them for.
 * @author jhoule
 */
public abstract class ColumnDescriptor {

     /**
     * returns the string of the item type in the XML that this handler is for.
     * it is required to return a valid String for all TagHandlers in order to make
     * the HandlerFactory work correctly.
     * @return the type this handler handles.
     */
    public abstract String getTypeHandled();

    /**
     * returns the string that should be used when labeling the results of this
     * tag parser.
     * @return the "label" for the Tag's results.
     */
    public abstract String getFriendlyName();

    /**
     * returns a Doublet (map entry) where the Key is the "friendly name" for
     * the column, and the type/parameter it stores the information for.
     * @return
     */
    public Doublet<String, String> toColMapEntry()
    {
        return new Doublet<String, String>(getFriendlyName(), getTypeHandled());
    }
}
