package ro.ciacob.maidens.legacy.exporters {
    import ro.ciacob.maidens.generators.constants.ClefTypes;
    import ro.ciacob.maidens.generators.constants.BarTypes;
    import ro.ciacob.math.Fraction;
    import eu.claudius.iacob.music.helpers.Divisions;
    import ro.ciacob.utils.NumberUtil;
    import ro.ciacob.maidens.generators.constants.duration.DotTypes;

    public class MusicXMLTranslator {
        public function MusicXMLTranslator() {
            // Empty
        }

        /**
         * Converts a given fraction denominator to an XML note `type`. We only support values
         * from `1` to `64`.
         */
        public static function getXMLNoteType(denominator:int):String {
            var noteType:String = '';
            switch (denominator) {
                case 1:
                    noteType = "whole";
                    break;
                case 2:
                    noteType = "half";
                    break;
                case 4:
                    noteType = "quarter";
                    break;
                case 8:
                    noteType = "eighth";
                    break;
                case 16:
                    noteType = "16th";
                    break;
                case 32:
                    noteType = "32nd";
                    break;
                case 64:
                    noteType = "64th";
                    break;
            }
            return noteType;
        }

        /**
         * Details for building a clef.
         */
        public static function toXMLClef(clef:String):Object {
            var clefData:Object = {sign: 'G', line: '2', clefOctaveChange: '0'};
            switch (clef) {
                case ClefTypes.BASS:
                    clefData.sign = 'F';
                    clefData.line = '4';
                    break;
                case ClefTypes.TREBLE:
                    clefData.sign = 'G';
                    clefData.line = '2';
                    break;
                case ClefTypes.TENOR:
                    clefData.sign = 'C';
                    clefData.line = '4';
                    break;
                case ClefTypes.TENOR_MODERN:
                    clefData.sign = 'G';
                    clefData.line = '2';
                    clefData.clefOctaveChange = '-1';
                    break;
                case ClefTypes.CONTRABASS:
                    clefData.sign = 'F';
                    clefData.line = '4';
                    clefData.clefOctaveChange = '-1';
                    break;
                case ClefTypes.ALTO:
                    clefData.sign = 'C';
                    clefData.line = '3';
                    break;
            }
            return clefData;
        }

        /**
         * Type of custom bar to use.
         */
        public static function toXMLBar(barType:String):String {
            switch (barType) {
                case BarTypes.DOUBLE_BAR:
                    return "light-light";
                case BarTypes.FINAL_BAR:
                    return "light-heavy";
            }
            return "";
        }

        /**
         * Details for building a note.
         */
        public static function toXMLNote(
                duration:Fraction,
                pitchName:String = null, alteration:int = 0, octaveIndex:int = 0,
                tie:Boolean = false, dot : Fraction = null
            ):String {

            // TARGETS:
            // pitch:Pitch = null, accidental:String = null(?), tie:String = null
            // inChord:Boolean = false (!),
            // voice:String = null (!),

            var noteData:Object = {};

            if (duration) {
                // Note duration in MusicXML divisions
                noteData.duration = Divisions.getDivisionsFor(Divisions.SAFE_DIVISIONS_VALUE, duration);

                // Conventional, power-of-two duration, for graphical representation
                var graphicalDuration:Fraction = Divisions.getGraphicalTupletFraction(duration);
                noteData.type = getXMLNoteType(graphicalDuration.denominator);

                // How many dots to draw for this note. We only support the single (adds 1/2) or double (Adds 3/4) dots.
                if (dot && dot.equals(Fraction.ZERO)) {
                    noteData.numDots = (dot.equals(Fraction.fromString(DotTypes.SINGLE))? 1 : 2);
                }

            }

            return JSON.stringify(noteData, null, '\t');
        }

        /**
         * Time signature information.
         */
        public static function toXMLTimeSignature (timeSignature:Array) : String {
            return JSON.stringify ({
                beats: timeSignature[0],
                beatType: timeSignature[1]
            }, null, '\t');
        }

        /**
         * Information for custom bar types.
         */
        public static function toXMLBarline (barType: String) : String {
			return "to do";
        }

    }
}