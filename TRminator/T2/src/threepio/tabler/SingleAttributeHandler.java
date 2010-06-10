/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */

package threepio.tabler;

import java.util.HashMap;
import threepio.documenter.XTag;
import threepio.tabler.container.Table;

/**
 *
 * @author jhoule
 */
public abstract class SingleAttributeHandler {

    public SingleAttributeHandler()
    {
       
    }

    public abstract void handle(XTag t, Table table, String curRowName);

    public abstract String handles();
}


