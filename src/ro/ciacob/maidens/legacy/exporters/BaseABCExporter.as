package ro.ciacob.maidens.legacy.exporters {

    import ro.ciacob.desktop.data.exporters.IExporter;
    import ro.ciacob.math.Fraction;

    /**
     * Specific exporter that translates a MAIDENS score in the "Music ABC" format.
     * @see AbstractExporter
     */
    public class BaseABCExporter extends AbstractExporter implements IExporter {
        public function BaseABCExporter() {
            super();
            currentMidiChannel = 0;
        }

        /**
         * Transforms user-provided strings in Music ABC-safe strings.
         * @see AbstractExporter.sanitizeUserString
         */
        override protected function sanitizeUserString(text:String):String {
            if (!text) {
                return '';
            }
            text = text.replace(/\x5c/g, '\\\\') // backslash
                .replace(/\x25/g, '\\%') // percent symbol
                .replace(/\x26/g, '\\&') // ampersand
                .replace(/\x22/g, '\\u0022') // double quotes
                .replace(/©/g, '\\u00a9') // copyright symbol
                .replace(/♭/g, '\\u266d') // flat symbol
                .replace(/♮/g, '\\u266e') // natural symbol
                .replace(/♯/g, '\\u266f') // sharp symbol
                .replace(/\r\n|\n|\r/g, '$&+:'); // new line continuation

            return text;
        }

        /**
         * Translates a MAIDENS time signature into a Music ABC format time signature.
         * @see AbstractExporter.translateTimeSignature
         */
        override protected function translateTimeSignature(timeSignature:Array):String {
            return ABCTranslator.translateTimeSignature(timeSignature);
        }

        /**
         * Translates a MAIDENS bar type into a Music ABC format bar type.
         * @see AbstractExporter.translateBarType
         */
        override protected function translateBarType(barType:String):String {
            return ABCTranslator.translateBarType(barType);
        }

        /**
         * Returns the MIDI program (aka "patch") number for a given part.
         * @see AbstractExporter.getMidiPatch
         */
        override protected function getMidiPatch(partData:Object):int {
            const patch:int = super.getMidiPatch(partData);
            return patch - 1;
        }

        /**
         * Translates a MAIDENS clef symbol into a Music ABC format clef definition.
         * @see AbstractExporter.translateClef
         */
        override protected function translateClef(clef:String):String {
            return ABCTranslator.translateClef(clef);
        }

        /**
         * Translates a MAIDENS note into a Music ABC format note.
         * @see ABCTranslator.translateNote
         */
        override protected function translateNote(
                duration:Fraction,
                pitchName:String, alteration:int, octaveIndex:int,
                tie:Boolean = false, dot:Fraction = null
            ):String {

            return ABCTranslator.translateNote(
                    duration, pitchName,
                    alteration, octaveIndex, tie
                );
        }

        /**
         * Translates a MAIDENS rest into a Music ABC format rest.
         * @see ABCTranslator.translateRest
         */
        override protected function translateRest(duration:Fraction, visibleRest:Boolean = true):String {
            return ABCTranslator.translateRest(duration, visibleRest);
        }
    }
}
