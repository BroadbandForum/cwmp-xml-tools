/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */

package threepio.engine;

import threepio.container.Doublet;

/**
 *
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

    public Doublet<String, String> toColMapEntry()
    {
        return new Doublet<String, String>(getFriendlyName(), getTypeHandled());
    }
}
