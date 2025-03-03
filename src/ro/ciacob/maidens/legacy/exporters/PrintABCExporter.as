package ro.ciacob.maidens.legacy.exporters {
import flash.filesystem.File;

import ro.ciacob.maidens.legacy.constants.FileAssets;


/**
 * TO DO: investigate whether, apart from lacking annotations, the printable score should
 * diverge from the on-screen score. For the time being, there is not another difference
 * (annotations are added in a dedicated subclass of BaseAbcExporter, so there is nothing
 * we need to do here).
 */
public class PrintABCExporter extends VisualABCExporter {
    public function PrintABCExporter() {
        super();
    }

    override protected function get templateFile():File {
        return FileAssets.TEMPLATES_DIR.resolvePath(FileAssets.ABC_PRINT);
    }
}
}
