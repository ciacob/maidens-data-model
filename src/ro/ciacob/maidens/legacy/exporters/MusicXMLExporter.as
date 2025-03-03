package ro.ciacob.maidens.legacy.exporters {
    import ro.ciacob.desktop.data.exporters.IExporter;
    import ro.ciacob.desktop.data.DataElement;
    import eu.claudius.iacob.music.wrappers.Score;
    import ro.ciacob.maidens.legacy.ModelUtils;
    import ro.ciacob.maidens.legacy.ProjectData;
    import ro.ciacob.maidens.legacy.constants.DataFields;
    import eu.claudius.iacob.music.wrappers.Creator;
    import ro.ciacob.utils.Time;
    import eu.claudius.iacob.music.wrappers.Misc;
    import eu.claudius.iacob.music.wrappers.Identification;
    import ro.ciacob.utils.Descriptor;
    import eu.claudius.iacob.music.wrappers.PageMargins;
    import eu.claudius.iacob.music.wrappers.Scaling;
    import eu.claudius.iacob.music.wrappers.PartInfo;
    import eu.claudius.iacob.music.wrappers.Group;
    import eu.claudius.iacob.music.wrappers.PartContent;
    import eu.claudius.iacob.music.builders.MusicXMLBuilder;
    import ro.ciacob.math.Fraction;
    import flash.filesystem.File;

    /**
     * This file is part of the Maidens Data Model project.
     *
     * @file MusicXMLExporter.as
     * @path /D:/_DEV_/github/actionscript/maidens-data-model/src/ro/ciacob/maidens/legacy/exporters/
     *
     * This class is responsible for exporting music data to the MusicXML format.
     */
    public class MusicXMLExporter extends AbstractExporter implements IExporter {

        private static const SCORE_WIDTH:String = "1239.96";
        private static const SCORE_HEIGHT:String = "1753.66";
        private static const SCORE_MARGINS:Vector.<PageMargins> = Vector.<PageMargins>([
                    new PageMargins("59.0458", "59.0458", "206.66", "59.0458", "both")
                ]);
        private static const SCORE_SCALING:Scaling = new Scaling("6.7744", "40");

        public function MusicXMLExporter() {
            // Empty
        }

        /**
         * Exports the provided data to the MusicXML format.
         *
         * @param   data
         *          `DataElement` instance representing the root node of a MAIDENS project. The function
         *          actually requires the use of the `ProjectData` subclass; `DataElement` was used to
         *          comply with the IExporter interface.
         *
         * @param   shallow
         *          Not used, included to comply with the IExporter interface. The MusicXML
         *          export is never shallow (it always descends into all needed levels such as
         *          Parts, Measures, Voices, etc.).
         *
         * @param   isRecursiveCall
         *          Not used, included to comply with the IExporter interface.
         *
         * @return  Returns an XML instance if `data` is a non-null `ProjectData` instance pointing
         *          to the root node of a MAIDENS project; otherwise returns `null`. Use
         *          `toXMLString()` on the returned XML instance to obtain the actual content to be
         *          written to an *.xml file.
         */
        override public function export(data:DataElement, shallow:Boolean = false, isRecursiveCall:Boolean = false):* {
            var project:ProjectData = (data as ProjectData);
            if (project && ModelUtils.isProject(project)) {
                super.resetAll();
                ModelUtils.updateUnifiedPartsList(project);
                const interimData:Object = super.buildTemplateData(project);

                trace(JSON.stringify(interimData, null, '\t'));

                // TITLE
                const title:String = project.getContent(DataFields.PROJECT_NAME) as String;

                // IDENTIFICATION
                // Creators
                const creators:Vector.<Creator> = new Vector.<Creator>;
                const composerName:String = project.getContent(DataFields.COMPOSER_NAME) as String;
                if (composerName && composerName !== DataFields.VALUE_NOT_SET) {
                    creators.push(new Creator('composer', composerName));
                }

                // Encoding
                const defaultTime:String = Time.toFormat(Time.now, Time.TIMESTAMP_DEFAULT);
                const encoder:String = Descriptor.getAppSignature(true);

                var encodingDate:String = project.getContent(DataFields.MODIFICATION_TIMESTAMP) as String;
                if (!encodingDate || encodingDate === DataFields.VALUE_NOT_SET) {
                    encodingDate = defaultTime;
                }

                // Miscellaneous
                const misc:Vector.<Misc> = new Vector.<Misc>;

                var creationTime:String = project.getContent(DataFields.CREATION_TIMESTAMP) as String;
                if (!creationTime || creationTime === DataFields.VALUE_NOT_SET) {
                    creationTime = defaultTime;
                }

                var modificationTime:String = project.getContent(DataFields.MODIFICATION_TIMESTAMP) as String;
                if (!modificationTime || modificationTime === DataFields.VALUE_NOT_SET) {
                    modificationTime = defaultTime;
                }

                misc.push(
                        new Misc("creation timestamp", creationTime),
                        new Misc("modification timestamp", modificationTime)
                    );

                var copyrightNote:String = project.getContent(DataFields.COPYRIGHT_NOTE) as String;
                if (copyrightNote && copyrightNote !== DataFields.VALUE_NOT_SET) {
                    misc.push(new Misc("copyright note", copyrightNote));
                }

                var customNotes:String = project.getContent(DataFields.CUSTOM_NOTES) as String;
                if (customNotes && customNotes !== DataFields.VALUE_NOT_SET) {
                    misc.push(new Misc("custom notes", customNotes));
                }

                const identification:Identification = new Identification(creators, encoder, encodingDate, misc);

                // Assemble and return an equivalent Score instance.
                const score:Score = new Score(
                        title, identification,
                        SCORE_WIDTH, SCORE_HEIGHT,
                        SCORE_MARGINS, SCORE_SCALING,
                        _buildPartsInfo(project),
                        _buildPartsContent(project),
                        _buildGroupsInfo(project)
                    );
                return MusicXMLBuilder.buildScore(score);

            }
            return null;
        }

        /**
         * Replaces XML special characters with their entity equivalents.
         * @see AbstractExporter.sanitizeUserString
         */
        override protected function sanitizeUserString(str:String):String {
            if (!str)
                return ""; // Handle null or empty input safely

            return str.replace(/&/g, "&amp;")
                .replace(/</g, "&lt;")
                .replace(/>/g, "&gt;")
                .replace(/"/g, "&quot;")
                .replace(/'/g, "&apos;");
        }

        /**
         * Translates a MAIDENS clef symbol into a MusicXML format clef definition.
         * @see AbstractExporter.translateClef
         */
        override protected function translateClef(clef:String):String {
            return JSON.stringify(MusicXMLTranslator.toXMLClef(clef), null, '\t');
        }

        /**
         * Translates a MAIDENS bar type into a MusicXML format bar type.
         * @see AbstractExporter.translateBarType
         */
        override protected function translateBarType(barType:String):String {
            return MusicXMLTranslator.toXMLBar(barType);
        }

        /**
         * Translates a MAIDENS note into a Music XML format note.
         * @see AbstractExporter.translateNote
         */
        override protected function translateNote (
                duration:Fraction,
                pitchName:String, alteration:int, octaveIndex:int,
                tie:Boolean = false, dot:Fraction = null
            ):String {
            
            return MusicXMLTranslator.toXMLNote (duration, pitchName, alteration, octaveIndex, tie, dot);
        }

        /**
         * Translates a MAIDENS time signature into a MusicXML format time signature.
         * @see AbstractExporter.translateTimeSignature
         */
        override protected function translateTimeSignature(timeSignature:Array):String {
            return MusicXMLTranslator.toXMLTimeSignature(timeSignature);
        }

        /**
         * Translates a MAIDENS rest into a MusicXML format rest.
         */
        override protected function translateRest(duration:Fraction, visibleRest:Boolean = true):String {
            return MusicXMLTranslator.toXMLNote (duration);
        }

        /**
         * Overridden to satisfy superclass constraint, but not needed.
         */
        override protected function get templateFile():File {
            return null;
        }

        private function _buildPartsInfo(source:ProjectData):Vector.<PartInfo> {
            const info:Vector.<PartInfo> = new Vector.<PartInfo>;
            // TODO: implement

            return info;
        }

        private function _buildGroupsInfo(source:ProjectData):Vector.<Group> {
            const groups:Vector.<Group> = new Vector.<Group>;
            // TODO: implement

            return groups;
        }

        private function _buildPartsContent(source:ProjectData):Vector.<PartContent> {
            const content:Vector.<PartContent> = new Vector.<PartContent>;
            // TODO: implement

            return content;
        }

    }
}