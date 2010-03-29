/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */

package trminator;

import threepio.engine.ThreepioUI;

/**
 * TRminatorUI is a base class for User Interfaces to TRminator.
 * Here, the mandatory functions are defined for a usable UI with the TRminator
 * functionality.
 * This is an extension of ThreepioUI.
 * @author jhoule
 * @see ThreepioUI
 */
public abstract class TRminatorUI extends ThreepioUI implements Runnable{

    /**
     * The Application the UI is running on top of.
     */
    TRminatorApp myApp;

    /**
     * No-argument constructor.
     * Currently, this is not used.
     * @throws NoSuchMethodException
     */
    TRminatorUI() throws NoSuchMethodException
    {
        throw new NoSuchMethodException("not implemented");
    }

    /**
     * Constructor.
     * The TRminatorApp passed is so that the myApp poitner can be initialized.
     * @param app
     */
    TRminatorUI(TRminatorApp app)
    {
        myApp = app;
    }

    /**
     * Updates the instance variables in myApp (the linked TRminator app) based on
     * the input from the User.
     * @throws Exception - when there is a type/range or other value conflict.
     */
    protected abstract void updateVariables() throws Exception;

    /**
     * Updates the instance variables and fields of the UI to reflect the values
     * in myApp (the linked TRminator App).
     */
    protected abstract void updateFields();

    /**
     * Displays the message to the user in whatever way the UI decides to do so.
     * @param msg - the message to give to the user.
     */
    protected abstract void updateStatus(String msg);

}
