/*
 * File: Documenter.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.documenter;

import java.io.File;
import java.util.Map.Entry;

/**
 * Documenter is an interface defining the medthods and variables common to
 * classes that convert objects and files to Doc objects.
 * @author jhoule
 */
public interface Documenter
{

    /**
     * Converts a file according to the specific parameters of the Qer.
     * @param f - the file
     * @return the document.
     */
    Doc convertFile(File f) throws Exception;

    /**
     * converts a file, giving it the version that is the value in the entry.
     * @param info - the entry
     * @return the document.
     */
    Doc convertFile(Entry<String, String> info) throws Exception;
}
