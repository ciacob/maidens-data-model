package ro.ciacob.maidens.legacy.exporters {
    import ro.ciacob.desktop.data.exporters.IExporter;
    import ro.ciacob.desktop.data.DataElement;
    import ro.ciacob.utils.Templates;
    import flash.filesystem.File;
    import ro.ciacob.maidens.legacy.ProjectData;
    import ro.ciacob.maidens.legacy.constants.DataFields;
    import ro.ciacob.utils.Descriptor;
    import eu.claudius.iacob.maidens.Colors;
    import ro.ciacob.maidens.legacy.ModelUtils;
    import ro.ciacob.utils.constants.CommonStrings;
    import ro.ciacob.utils.ConstantUtils;
    import ro.ciacob.maidens.generators.constants.parts.PartNames;
    import ro.ciacob.maidens.generators.constants.parts.GMPartMidiPatches;
    import ro.ciacob.desktop.signals.PTT;
    import eu.claudius.iacob.maidens.constants.ViewKeys;
    import ro.ciacob.maidens.generators.constants.BarTypes;
    import ro.ciacob.maidens.legacy.constants.Voices;
    import ro.ciacob.math.Fraction;
    import ro.ciacob.maidens.legacy.constants.StaticFieldValues;
    import ro.ciacob.maidens.generators.constants.pitch.PitchAlterationTypes;
    import eu.claudius.iacob.maidens.constants.ViewPipes;

    /**
     * Provides a generic framework for implementing specific exporters.
     * An "exporter" class is one that takes as input the internal MAIDENS data model
     * that represents a musical score and produces, as output, an equivalent score in
     * a different format, e.g., "Music ABC" or "MusicXML".
     */
    public class AbstractExporter implements IExporter {
        protected static const BAR:String = 'bar';
        protected static const CHARSET:String = 'utf-8';
        protected static const CREATOR_SOFTWARE:String = 'creatorSoftware';
        protected static const SCORE_BACKGROUND:String = 'scoreBackground';
        protected static const SCORE_FOREGROUND:String = 'scoreForeground';
        protected static const EVENTS:String = 'events';
        protected static const MEASURES:String = 'measures';
        protected static const SECTIONS:String = 'sections';
        protected static const SECTION_NAME:String = 'name';
        protected static const TIME_SIGNATURE:String = 'timeSignature';

        protected const SUBSCRIBE:Function = PTT.getPipe().subscribe;
        protected const SEND:Function = PTT.getPipe().send;
        protected const UNSUBSCRIBE:Function = PTT.getPipe().unsubscribe;

        protected const MEASURE_PADDING_PIPE:PTT = PTT.getPipe(ViewPipes.MEASURE_PADDING_PIPE);

        protected var persistentAlterations:Object;
        protected var pitchesMap:Object;
        protected var stavesUidDictionary:Object;
        protected var timeSignature:Array = null;
        protected var lastTupletMarker:TupletMarker;
        protected var paddingDurations:Array;
        protected var currentMidiChannel:int;

        public function AbstractExporter() {
            if (Object(this).constructor == AbstractExporter) {
                throw new Error(
                        "Class `AbstractExporter` is abstract and cannot be instantiated directly."
                    );
            }
        }

        /**
         * @see ro.ciacob.desktop.data.exporters.IExporter#export
         */
        public function export(data:DataElement, shallow:Boolean = false, isRecursiveCall:Boolean = false):* {
            var project:ProjectData = (data as ProjectData);
            if (project && ModelUtils.isProject(project)) {
                resetAll();
                var templateData:Object = buildTemplateData(project);
                return Templates.fillSimpleTemplate(templateFile, templateData);
            }
            return null;
        }

        /**
         * Resets all internal storage and context, readying the class for a new export operation.
         */
        protected function resetAll():void {
            persistentAlterations = {};
            pitchesMap = {};
            stavesUidDictionary = {};
            lastTupletMarker = null;
            timeSignature = null;
            MeasurePaddingMarker.reset();
        }

        /**
         * Creates a template friendly data source from a given project.
         * @param    project
         *            A project to extract data from.
         *
         * @return    An object to run against the template engine.
         */
        protected function buildTemplateData(project:ProjectData):Object {
            var templateData:Object = {};
            buildHeaderData(project, templateData);
            buildBodyData(project);
            return templateData;
        }

        /**
         * Copies, and translates as needed, the data between a given source project and
         * an implied `staff` target object. Resulting data is meant to populate the
         * "music body" (by providing measures, notes and so on).
         *
         * @param    project
         *           The project to extract information from, if needed.
         */
        protected function buildBodyData(project:ProjectData):void {
            var partUid:String;
            var partNode:ProjectData;
            var partEquivalentSignature:String;
            var transcribedEqSigns:Array;
            var transcribedUids:Array;
            for (var i:int = 0; i < ModelUtils.sectionsOrderedList.length; i++) {
                var sectionName:String = ModelUtils.sectionsOrderedList[i];
                var partsInCurrentSection:Object = ModelUtils.partsPerSection[sectionName];
                // We first transcribe the parts that play in the current section.
                transcribedEqSigns = [];
                transcribedUids = [];
                for (var partName:String in partsInCurrentSection) {
                    var partInstances:Array = (partsInCurrentSection[partName] as Array);
                    for (var partIdx:int = 0; partIdx < partInstances.length; partIdx++) {
                        partUid = (partInstances[partIdx] as String);
                        partNode = (ModelUtils.partsUidsToNodesMap[partUid] as ProjectData);
                        buildPartData(partNode, sectionName);
                        partEquivalentSignature = ModelUtils.getPartEquivalentSignature(partNode);
                        transcribedEqSigns.push(partEquivalentSignature);
                        transcribedUids.push(partUid);
                    }
                }
                // Then, we add blank measures for the ones that don't.
                for (var j:int = 0; j < ModelUtils.unifiedPartsList.length; j++) {
                    var partData:Object = (ModelUtils.unifiedPartsList[j] as Object);
                    partUid = (partData[DataFields.PART_UID] as String);
                    partNode = (ModelUtils.partsUidsToNodesMap[partUid] as ProjectData);
                    partEquivalentSignature = ModelUtils.getPartEquivalentSignature(partNode);
                    var wasntTranscribed:Boolean = (transcribedEqSigns.indexOf(partEquivalentSignature) ==
                            -1);
                    if (wasntTranscribed) {
                        var modelForBlanks:ProjectData = (ModelUtils.partsUidsToNodesMap[transcribedUids[0] as
                                    String]);
                        buildPartData(partNode, sectionName, modelForBlanks);
                    }
                }
            }
        }

        /**
         * @param    partNode
         *            The ProjectData representing the source part, which needs to be
         *            translated into third-party notation.
         *
         * @param    parentSectionName
         *            The name of the section containing the part which is to be translated.
         *
         * @param    modelForBlanks
         *            Optional. A part node whose measures are to be mimicked,
         *            but filled with whole note rests instead of the actual music.
         *            The part information will still be taken from `partNode`.
         */
        protected function buildPartData(
                partNode:ProjectData, parentSectionName:String,
                modelForBlanks:ProjectData = null):void {

            var partNumStaves:int = (partNode.getContent(DataFields.PART_NUM_STAVES) as int);
            for (var staffIdx:int = 0; staffIdx < partNumStaves; staffIdx++) {
                var abbrevPartName:String = partNode.getContent(DataFields.ABBREVIATED_PART_NAME);
                var partOrdNum:int = (partNode.getContent(DataFields.PART_ORDINAL_INDEX) as int);
                var rawStaffUid:String = buildStaffUid(abbrevPartName, partOrdNum, staffIdx);
                var staff:Object = stavesUidDictionary[rawStaffUid];
                if (staff) {
                    var sectionsStorage:Array = (staff.sections as Array);
                    if (sectionsStorage == null) {
                        sectionsStorage = [];
                        staff.sections = sectionsStorage;
                    }
                    var section:Object = {};
                    section.name = parentSectionName;
                    var measuresStorage:Array = provideMeasuresStorage(staff);
                    section.measures = measuresStorage;
                    var mustFillWithBlanks:Boolean = (modelForBlanks != null);
                    var partMeasures:Array = ModelUtils.getChildrenOfType(mustFillWithBlanks ?
                            modelForBlanks : partNode, DataFields.MEASURE);
                    for (var measIdx:int = 0; measIdx < partMeasures.length; measIdx++) {
                        var measureStorage:Object = {};
                        var measureNode:ProjectData = (partMeasures[measIdx] as ProjectData);
                        buildMeasureData(measureNode, measureStorage, staffIdx, mustFillWithBlanks);
                        measuresStorage.push(measureStorage);
                    }
                    sectionsStorage.push(section);
                }
            }
        }

        /**
         * Copies, and translates as needed, the data between a given measure node and
         * a target object. Resulting data is meant to provide measure content, like
         * time signature, notes, bar type, etc.
         *
         * @param    measure
         *            The measure note to extract data from.
         *
         * @param    storage
         *            An object to store extracted data into.
         *
         * @param    staffIndex
         *            The index of the staff currently being extracted, zero based.
         *
         * @param    forceBlanks
         *            Optional. If given, all music within the measure will be replaced with
         *            whole note rests. Defaults to false.
         */
        protected function buildMeasureData(measure:ProjectData, storage:Object, staffIndex:int,
                forceBlanks:Boolean = false):void {
            // Time signature
            SUBSCRIBE(ViewKeys.MEASURE_TIME_SIGNATURE_READY, _onTimeSignatureReady);
            SEND(ViewKeys.NEED_MEASURE_OWN_TIME_SIGNATURE, measure);
            var measureTimeSignature:String = (timeSignature != null) ? translateTimeSignature(timeSignature) : '';
            measureTimeSignature = measureTimeSignature.concat(CommonStrings.SPACE);

            // Bar type. If "auto", then it translates to a "thin-thick" bar for the last measure of the last
            // section, a "thin-thin" bar for the last measure of any other section, and to a "thin" (aka, regular)
            // bar for any other measure.
            var barType:String = (measure.getContent(DataFields.BAR_TYPE) as String);
            if (barType == BarTypes.AUTO_BAR) {
                if (ModelUtils.isLastMeasure(measure)) {
                    barType = BarTypes.FINAL_BAR;
                }
                else if (ModelUtils.isLastMeasureInSection(measure)) {
                    barType = BarTypes.DOUBLE_BAR;
                }
                else {
                    barType = BarTypes.NORMAL_BAR;
                }
            }

            var measureBar:String = translateBarType(barType);
            var events:Array = [];
            if (!forceBlanks) {
                // Notes (within voices); we pay attention to inheriting alterations as a
                // result of a tie across the barline
                pitchesMap = {};
                if (persistentAlterations != null) {
                    for (var persistedPitchMark:String in persistentAlterations) {
                        var persistedAlteration:int = persistentAlterations[persistedPitchMark];
                        pitchesMap[persistedPitchMark] = persistedAlteration;
                    }
                    persistentAlterations = null;
                }
                var voicesOnThisStaff:uint = 0;
                var voiceNodes:Array = ModelUtils.getChildrenOfType(measure, DataFields.VOICE);
                voiceNodes.sort(ModelUtils.compareVoiceNodes);
                for (var i:int = 0; i < voiceNodes.length; i++) {
                    if (voicesOnThisStaff >= Voices.NUM_VOICES_PER_STAFF) {
                        break;
                    }
                    var voiceNode:ProjectData = (voiceNodes[i] as ProjectData);
                    var voiceStaffIndex:int = (voiceNode.getContent(DataFields.STAFF_INDEX) as int) - 1;
                    if (voiceStaffIndex == staffIndex) {
                        voicesOnThisStaff++;
                        buildVoiceData(voiceNode, events);

                        // NOTE: we only render the second voice if it was given explicit
                        // content.
                    }
                }
                if (voicesOnThisStaff == 0) {
                    events.push(translateRest(Fraction.WHOLE));
                }
            }

            storage.timeSignature = measureTimeSignature;
            storage.events = events;
            storage.bar = measureBar;
            onAfterMeasureTranslation(measure, storage);
        }

        /**
         * Copies, and translates as needed, the data for one voice node. This will
         * create one or more melodic lines in a measure.
         *
         * @param    voice
         *           The voice node to extract data from.
         *
         * @param    storage
         *           An array to fill with strings representing musical notes.
         */
        protected function buildVoiceData(voice:ProjectData, storage:Array):void {
            var duration:Fraction = null;
            var dot:Fraction = null;
            lastTupletMarker = null;
            var mightHaveAnotherVoice:Boolean = (storage.length > 0);
            if (mightHaveAnotherVoice) {
                storage.push("&");
            }
            for (var clusterIdx:int = 0; clusterIdx < voice.numDataChildren; clusterIdx++) {
                var clusterNode:ProjectData = ProjectData(voice.getDataChildAt(clusterIdx));
                onBeforeClusterTranslation(clusterNode, storage);
                // Duration
                var durationSrc:String = (clusterNode.getContent(DataFields.CLUSTER_DURATION_FRACTION) as
                        String);
                if (durationSrc != DataFields.VALUE_NOT_SET) {
                    duration = Fraction.fromString(durationSrc);
                    // Dot
                    var dotSrc:String = (clusterNode.getContent(DataFields.DOT_TYPE) as String);
                    if (dotSrc != DataFields.VALUE_NOT_SET) {
                        dot = Fraction.fromString(dotSrc);
                        var toAdd:Fraction = duration.multiply(dot) as Fraction;
                        duration = duration.add(toAdd) as Fraction;
                    }
                    // Tuplet division
                    // TODO: SUPPORT NESTED TUPLETS
                    var clusterStartsTuplet:Boolean = (clusterNode.getContent(DataFields.STARTS_TUPLET) as Boolean);
                    if (clusterStartsTuplet) {
                        var srcNumBeats:int = clusterNode.getContent(DataFields.TUPLET_SRC_NUM_BEATS) as int;
                        if (srcNumBeats <= 0) {
                            srcNumBeats = StaticFieldValues.DEFAULT_TUPLET_SRC_BEATS;
                        }
                        var targetNumBeats:int = clusterNode.getContent(DataFields.TUPLET_TARGET_NUM_BEATS) as int;
                        if (targetNumBeats <= 0) {
                            targetNumBeats = StaticFieldValues.DEFAULT_TUPLET_TARGET_BEATS;
                        }
                        var haveTuplet:Boolean = (srcNumBeats != targetNumBeats);
                        if (haveTuplet) {
                            if (lastTupletMarker != null) {
                                sealTuplet(lastTupletMarker, true, storage);
                            }
                            var rawTupletBeatDuration:String = (clusterNode.getContent(DataFields.TUPLET_BEAT_DURATION) as String);
                            if (rawTupletBeatDuration == DataFields.VALUE_NOT_SET) {
                                rawTupletBeatDuration = (clusterNode.getContent(DataFields.CLUSTER_DURATION_FRACTION) as String);
                            }
                            var tupletBeatDuration:Fraction = Fraction.fromString(rawTupletBeatDuration);
                            var intrinsicTupletSpan:Fraction = tupletBeatDuration.multiply(new Fraction(srcNumBeats)) as Fraction;

                            // If the cluster that starts the tuplet has a duration greater than the intrinsic tuplet span, we force it to the
                            // tuplet beat duration instead; user will take it from there.
                            if (duration.greaterThan(intrinsicTupletSpan)) {
                                clusterNode.setContent(DataFields.CLUSTER_DURATION_FRACTION, (duration = tupletBeatDuration).toString());
                            }
                            lastTupletMarker = new TupletMarker(clusterNode.route, intrinsicTupletSpan, srcNumBeats, targetNumBeats);
                            storage.push(lastTupletMarker);
                        }
                    }
                    if (lastTupletMarker) {
                        var response:int = lastTupletMarker.accountFor(duration);

                        // If the duration of the current cluster does not fit in the tuplet, we produce a ghost
                        // rest to fill the tuplet up and move on.
                        if (response == TupletMarker.OVERFULL) {
                            sealTuplet(lastTupletMarker, true, storage);
                        }
                        else {

                            // If the duration of the current cluster perfectly fits in the tuplet (i.e., concludes, or completes
                            // the tuplet), we just seal/unlink the tuplet as it is, and move on.
                            if (response == TupletMarker.FULL) {
                                sealTuplet(lastTupletMarker);
                            }
                        }
                    }

                    // Notes & chords
                    var numNotes:int = clusterNode.numDataChildren;
                    if (numNotes > 0) {
                        var needsGrouping:Boolean = (numNotes > 1);
                        if (needsGrouping) {
                            storage.push("[");
                        }
                        for (var noteIdx:int = 0; noteIdx < clusterNode.numDataChildren; noteIdx++) {
                            var note:ProjectData = (clusterNode.getDataChildAt(noteIdx) as
                                    ProjectData);
                            // Pitch
                            var pitchName:String = (note.getContent(DataFields.PITCH_NAME) as String);
                            if (pitchName != DataFields.VALUE_NOT_SET) {
                                // Octave
                                var octaveIndex:int = (note.getContent(DataFields.OCTAVE_INDEX) as int);

                                // Alterations (not all have to be shown)
                                var pitchMark:String = pitchName.concat(octaveIndex);
                                if (pitchesMap[pitchMark] == null) {
                                    pitchesMap[pitchMark] = PitchAlterationTypes.NATURAL;
                                }
                                var currentAlteration:int = (note.getContent(DataFields.PITCH_ALTERATION) as int);
                                var mustShowAlteration:Boolean = false;
                                if (currentAlteration != pitchesMap[pitchMark]) {
                                    pitchesMap[pitchMark] = currentAlteration;
                                    mustShowAlteration = true;
                                }
                                // Tie
                                var mustTie:Boolean = false;
                                var tieSrc:Object = (note.getContent(DataFields.TIES_TO_NEXT_NOTE));
                                if (tieSrc) {
                                    mustTie = true;

                                    // Tying across the barline must persist the
                                    // alteration of he tied note into the new measure
                                    var isLastCluster:Boolean = (clusterIdx == voice.numDataChildren - 1);
                                    if (isLastCluster) {
                                        if (persistentAlterations == null) {
                                            persistentAlterations = {};
                                        }
                                        persistentAlterations[pitchMark] = currentAlteration;
                                    }
                                }
                                var musicalNote:String = translateNote(duration, pitchName,
                                        (mustShowAlteration ? currentAlteration : PitchAlterationTypes.HIDE),
                                        octaveIndex, mustTie, dot);
                                storage.push(musicalNote);
                            }
                        }
                        if (needsGrouping) {
                            storage.push("]");
                        }
                    }
                    else {
                        var musicalRest:String = translateRest(duration);
                        storage.push(musicalRest);
                    }
                }
            }

            // If there is any leftover tuplet, close it properly
            if (lastTupletMarker) {
                sealTuplet(lastTupletMarker, true, storage);
            }

            // We pad every voice with invisible rests to the same nominal
            // value (determined by comparing the current measure's time signature with
            // the effective duration of all its voices — and considering the greater
            // value). This way, all measures will always align correctly in multi-voice
            // and/or multi-part music.
            var paddingMarker:MeasurePaddingMarker = new MeasurePaddingMarker;
            storage.push(paddingMarker);
            paddingMarker.accountFor(voice);
        }

        /**
         * Copies, and translates as needed, the data between a given source project and
         * a target object. Resulting data is meant to populate "header" template fields.
         *
         * @param    project
         *            The project to extract, and translate data form.
         *
         * @param    target
         *            The object to write translated data into.
         */
        protected function buildHeaderData(project:ProjectData, target:Object):void {
            // Generic project data
            target[DataFields.PROJECT_NAME] = sanitizeUserString(project.getContent(DataFields.PROJECT_NAME));
            target[DataFields.COMPOSER_NAME] = sanitizeUserString(project.getContent(DataFields.COMPOSER_NAME));
            target[DataFields.CREATION_TIMESTAMP] = project.getContent(DataFields.CREATION_TIMESTAMP);
            target[DataFields.MODIFICATION_TIMESTAMP] = project.getContent(DataFields.MODIFICATION_TIMESTAMP);
            target[DataFields.CUSTOM_NOTES] = sanitizeUserString(project.getContent(DataFields.CUSTOM_NOTES));
            target[DataFields.COPYRIGHT_NOTE] = sanitizeUserString(project.getContent(DataFields.COPYRIGHT_NOTE));
            target.creatorSoftware = Descriptor.getAppSignature(true);
            target.scoreBackground = '#' + Colors.SCORE_BACKGROUND.toString(16);
            target.scoreForeground = '#' + Colors.SCORE_FOREGROUND.toString(16);

            // List of all parts to be drawn in the score
            if (ModelUtils.unifiedPartsList != null && ModelUtils.unifiedPartsList.length > 0) {
                if (target.staves == null) {
                    target.staves = [];
                }
                for (var i:int = 0; i < ModelUtils.unifiedPartsList.length; i++) {
                    var partData:Object = ModelUtils.unifiedPartsList[i];
                    var partName:String = (partData[DataFields.PART_NAME] as String);
                    if (partName != DataFields.VALUE_NOT_SET) {
                        var partNumStaves:int = (partData[DataFields.PART_NUM_STAVES] as int);
                        for (var staffIndex:int = 0; staffIndex < partNumStaves; staffIndex++) {
                            buildStaffHeaderData(partData, target, staffIndex);
                        }
                    }
                }
                sortStaves(target.staves as Array);
            }
        }

        /**
         * Copies, and translates as needed, the data for one staff definition.
         *
         * @param    partData
         *           An object containing definitions for the current part.
         *
         * @param    target
         *           The object to write translated data into.
         *
         * @param    staffIndex
         *           The zero-based index of this staff.
         */
        protected function buildStaffHeaderData(partData:Object, target:Object, staffIndex:int):void {
            var ordIdx:int = partData[DataFields.PART_ORDINAL_INDEX];
            var mustShowOrdNum:Boolean = (partData[ModelUtils.MUST_SHOW_ORDINAL_NUMBER] as Boolean);
            var abbrev:String = partData[DataFields.ABBREVIATED_PART_NAME];
            var staffUid:String = buildStaffUid(abbrev, ordIdx, staffIndex);
            var name:String = (partData[DataFields.PART_NAME] as String).concat(mustShowOrdNum ?
                    (CommonStrings.SPACE + (ordIdx + 1)) : '');
            var abbrevName:String = abbrev.concat(mustShowOrdNum ? (CommonStrings.SPACE + (ordIdx + 1)) : '');
            var patchNumber:String = getMidiPatch(partData).toString();
            var channelIndex:String = getNextMidiChannel().toString();
            var clefsList:Array = (partData[DataFields.PART_CLEFS_LIST] as Array);
            var clef:String = translateClef(clefsList[staffIndex]);
            var transposition:String = (partData[DataFields.PART_TRANSPOSITION] as int).toString();
            var staff:Object = {
                    uid: staffUid,
                    name: name,
                    abrevName: abbrevName,
                    clef: clef,
                    transposition: transposition,
                    patchNumber: patchNumber,
                    channelIndex: channelIndex
                };

            stavesUidDictionary[staffUid] = staff;
            (target.staves as Array).push(staff);
        }

        /**
         * Compiles and returns a string such as: `Pno.1-1`.
         *
         * @param    abbrevPartName
         *           The abbreviated name of this part
         *
         * @param    partOrdNum
         *           The ordinal number of this part (i.e., if two violins play in the same
         *           section, the first will have a ordinal number of `1`, and the second, `2`.
         *
         * @param    staffIndex
         *           The number of staff, zero based. For instance, a piano part, which
         *           typically uses two staves, will invoke this function twice, first with
         *           `staffIndex` set to 0, and then to 1.
         *
         * @return   The resulting string, such as Pno.1-1
         */
        protected function buildStaffUid(abbrevPartName:String, partOrdNum:int, staffIndex:int):String {
            var canonicalName:String = abbrevPartName.replace(/[^a-zA-Z0-9]/g, '');
            return canonicalName.concat(partOrdNum + 1, staffIndex + 1);
        }

        /**
         * Sorts staves according to their part order (which, in turn, is determined
         * based on the most likely ensemble these staves would fit it).
         *
         * @param    staves
         *            The staves to sort, as an Array. The Array is sorted in place.
         */
        protected function sortStaves(staves:Array):void {
            ModelUtils.sortStavesByPartOrder(staves);
        }

        /**
         * Returns the MIDI program (aka "patch") number for a given part.
         *
         * @param   partData
         *          Object with information about a given part including its name, abbreviated name, etc.
         *
         * @return  The MIDI program number.
         *
         * Note: if the third-party format represents MIDI patches/programs as 0-based, you will want to
         * overwrite this method, call its abstract implementation via `super`, and subtract `1` from
         * the returned computed value.
         */
        protected function getMidiPatch(partData:Object):int {
            var patch:int = 1;
            try {
                var cleanPartName:String = partData[DataFields.PART_NAME].split(CommonStrings.BROKEN_VERTICAL_BAR).pop();
                var partInternalName:String = ConstantUtils.getNamesByMatchingValue(PartNames, cleanPartName)[0];
                patch = GMPartMidiPatches[partInternalName];
            }
            catch (e:Error) {
                trace('AbstractExporter:getMidiPatch() failed and defaulted to `1`. Error: ' +
                        e.message +
                        '\npartData:\n' +
                        JSON.stringify(partData, null, '\t')
                    );
            }
            return patch;
        }

        /**
         * Returns the next available MIDI channel, skipping channel 10, which is traditionally
         * assigned to unpitched percussion instruments, which MAIDENS does not have.
         *
         * @return The next available MIDI channel.
         *
         * Note: if the third-party format represents MIDI channels as 0-based, you will want to
         * overwrite this method, call its abstract implementation via `super`, and subtract `1` from
         * the returned computed value.
         */
        protected function getNextMidiChannel():int {
            return ((++currentMidiChannel < 10) ? currentMidiChannel : currentMidiChannel + 1);
        }

        /**
         * Overridable method that produces the Array to store each section's measures in. This Array will be populated
         * with Objects that each hold information about a measure's time signature, events (notes and rests) and
         * barline type. A class overriding this method can manipulate the stream of measures globally, e.g., it could
         * introduce an "off-the-records" lead-in measure.
         */
        protected function provideMeasuresStorage(staff:Object):Array {
            return [];
        }

        /**
         * This function is called after each "measure" element was processed.
         * You can overwrite it to amend the translation, e.g., by inserting some sort of annotation before the
         * closing bar of the measure.
         */
        protected function onAfterMeasureTranslation(measure:ProjectData, storage:Object):void {
            // Subclasses can override
        }

        /**
         * This function is called just before starting to process a "cluster" element.
         * You can overwrite it to modify the cluster, to prefix its translation with some
         * value, etc.
         */
        protected function onBeforeClusterTranslation(clusterNode:ProjectData, storage:Array):void {
            // Subclasses can override
        }

        /**
         * Translates a MAIDENS clef symbol into a third-party format clef definition.
         * @param	clef
         * 			The clef to translate, expressed as a string.
         *
         * Note: subclasses must override this method and provide an implementation.
         *
         * @return	The translated clef or an equivalent.
         */
        protected function translateClef(clef:String):String {
            throw new Error("Method translateClef() must be overridden in a subclass.");
            return null;
        }

        /**
         * Translates a MAIDENS time signature into a third-party format time signature.
         *
         * @param	timeSignature
         * 			The time signature to translate, expressed as an Array of two integers,
         *          the first being the number of beats per measure, and the second, the note value.
         *
         * Note: subclasses must override this method and provide an implementation.
         *
         * @return	The translated time signature or an equivalent.
         */
        protected function translateTimeSignature(timeSignature:Array):String {
            throw new Error("Method translateTimeSignature() must be overridden in a subclass.");
            return null;
        }

        /**
         * Translates a MAIDENS note into a third-party format note.
         * @param	duration
         * 			The duration of the note.
         *
         * @param	pitchName
         * 			The name of the pitch, e.g., "C", "D", "E", etc.
         *
         * @param	alteration
         * 			The alteration of the pitch, e.g., `-1` for a flat, `1` for a sharp, `0` for natural.
         *
         * @param	octaveIndex
         * 			The index of the octave. MAIDENS uses `4` as the middle octave.
         *
         * @param	tie
         * 			Optional, default false. Whether the note should be tied to the next one or not.
         * 
         * @param   dot
         *          Optional, default null. The duration of the augmentation dot, e.g. `1/2` for a single
         *          dot or `3/4` for a double dot. A defined `0/1` dot is equivalent to a not defined
         *          dot.
         *
         * Note: subclasses must override this method and provide an implementation.
         *
         * @return	The translated note or an equivalent.
         */
        protected function translateNote(
                duration:Fraction,
                pitchName:String, alteration:int, octaveIndex:int,
                tie:Boolean = false, dot:Fraction = null
            ):String {
            throw new Error("Method translateNote() must be overridden in a subclass.");
            return null;
        }

        /**
         * Translates a MAIDENS rest into a third-party format rest.
         * @param   duration
         *          The duration of the rest.
         *
         * @param   visibleRest
         *          Whether the rest should be visible or not.
         *
         * Note: subclasses must override this method and provide an implementation.
         *
         * @return  The translated rest or an equivalent.
         */
        protected function translateRest(duration:Fraction, visibleRest:Boolean = true):String {
            throw new Error("Method translateTimeSignature() must be overridden in a subclass.");
            return null;
        }

        /**
         * Translates a MAIDENS bar type into a third-party format bar type.
         * @param	barType
         * 			The bar type to translate, expressed as a string.
         *
         * Note: subclasses must override this method and provide an implementation.
         *
         * @return	The translated bar type or an equivalent.
         */
        protected function translateBarType(barType:String):String {
            throw new Error("Method translateBarType() must be overridden in a subclass.");
            return null;
        }

        /**
         * Returns a file containing the template to be populated by this IExporter implementor.
         * Note that, while customary, using a template is not mandatory
         *
         * Note: subclasses must override this method and provide an implementation.
         *
         * @return An existing file.
         */
        protected function get templateFile():File {
            throw new Error("Method templateFile() must be overridden in a subclass.");
            return null;
        }

        /**
         * Generic-purpose function to transform user-provided strings into their "sanitized" counterparts.
         * This is especially important if the target format is sensible to special characters,e.g., XML.
         *
         * @param str The original string.
         * @return The "sanitized" string.
         *
         * Note: subclasses must override this method and provide an implementation, at the very least
         * returning the original string.
         */
        protected function sanitizeUserString(str:String):String {
            throw new Error("Method sanitizeUserString() must be overridden in a subclass.");
            return null;
        }

        /**
         * Executed when information about the time signature of the measure being translated becomes available.
         * @param   timeSignature
         *          The received time signature, as an Array of two integers, the first being the number
         *          of beats per measure, and the second, the note value.
         */
        private function _onTimeSignatureReady(timeSignature:Array):void {
            UNSUBSCRIBE(ViewKeys.MEASURE_TIME_SIGNATURE_READY, _onTimeSignatureReady);
            this.timeSignature = timeSignature;
        }

        /**
         * Unlinks the current tuplet marker so that it cannot account for any more clusters. Optionally,
         * right-pads it with ghost rests up to its nominal duration.
         */
        private function sealTuplet(tupletMarker:TupletMarker, rightPad:Boolean = false, storage:Array = null):void {
            if (rightPad && storage) {

                // Cache to conserve CPU
                var $remainder:Fraction = tupletMarker.remainder;

                // Compute the duration needed to properly fill-up the tuplet. Split it into simple
                // durations (i.e., we don't want dots here) and add the results as ghost rests
                // inside the tuplet.
                var tupletGhostRests:Array = [];
                _splitRawDuration($remainder);
                var fillUpDuration:Fraction;
                for (var j:int = 0; j < paddingDurations.length; j++) {
                    fillUpDuration = paddingDurations[j] as Fraction;
                    tupletMarker.accountFor(fillUpDuration);
                    tupletGhostRests.push(translateRest(fillUpDuration));
                }

                // Make sure we don't "steal" the annotation from the next "legit" cluster node:
                // try to insert the ghost rest(s) that fill up the tuplet BEFORE any trailing
                // annotation code.
                var i:int = storage.length - 1;
                while (i >= 0) {
                    var lastStorageEntry:String = storage[i] as String;
                    if (!lastStorageEntry) {
                        // Might be a Marker, therefore, not a String
                        i--;
                        continue;
                    }
                    var haveTrailingAnnotation:Boolean = lastStorageEntry.indexOf(CommonStrings.BROKEN_VERTICAL_BAR) != -1;
                    if (haveTrailingAnnotation) {
                        var args:Array = [i, 0].concat(tupletGhostRests);
                        storage.splice.apply(null, args);
                    }
                    else {
                        storage.push.apply(null, tupletGhostRests);
                    }
                    break;
                }
            }
            lastTupletMarker = null;
        }

        /**
         * Requests for and waits for a duration split task to be completed.
         * @param   duration
         *          A (possibly complex) duration to split into simple ones.
         */
        private function _splitRawDuration(duration:Fraction):void {

            MEASURE_PADDING_PIPE.subscribe(ViewKeys.DURATION_SPLIT_READY, _onDurationSplitReady);
            MEASURE_PADDING_PIPE.send(ViewKeys.SPLIT_DURATION_NEEDED, duration);
        }

        /**
         * Executed when the duration split task is completed.
         * @param   data
         *          The split duration, as an Array of simple durations.
         */
        private function _onDurationSplitReady(data:Object):void {
            MEASURE_PADDING_PIPE.unsubscribe(ViewKeys.DURATION_SPLIT_READY, _onDurationSplitReady);
            paddingDurations = (data as Array);
            paddingDurations.reverse();
        }
    }
}