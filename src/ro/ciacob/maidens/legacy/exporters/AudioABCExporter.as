package ro.ciacob.maidens.legacy.exporters {
    import flash.filesystem.File;
    import ro.ciacob.desktop.data.DataElement;
    import ro.ciacob.maidens.legacy.constants.FileAssets;

    public class AudioABCExporter extends BaseABCExporter {

        override protected function get templateFile():File {
            return FileAssets.TEMPLATES_DIR.resolvePath(FileAssets.ABC_AUDIO);
        }
    }
}
