/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */

package trminator;

import threepio.engine.ThreepioUI;

/**
 *
 * @author jhoule
 */
public abstract class TRminatorUI extends ThreepioUI implements Runnable{

    TRminatorApp myApp;

    TRminatorUI() throws NoSuchMethodException
    {
        throw new NoSuchMethodException("not implemented");
    }

    TRminatorUI(TRminatorApp app)
    {
        myApp = app;
    }

    protected abstract void updateStatus();

}
