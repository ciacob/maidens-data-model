package ro.ciacob.maidens.legacy.exporters {
    import ro.ciacob.maidens.generators.constants.ClefTypes;

    public class MusicXMLTranslator {
        public function MusicXMLTranslator() {
            // Empty
        }

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

    }
}