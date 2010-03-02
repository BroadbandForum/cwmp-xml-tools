/*
 * File: Versioned.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.container;

/**
 * Versioned is a simple interface, where a String version should be get-able and set-able.
 * Makes the code simpler, and makes sure that things that need versions do something about that.
 * @author jhoule
 */
public interface Versioned
{

    /**
     * returns the version of the object.
     * @return the version
     */
    public String getVersion();

    /**
     * sets the version of the object.
     * @param v - the new version
     */
    public void setVersion(String v);
}
