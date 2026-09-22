        NoteObject *garden = MakeNote(library, @"Weekend garden",
            @"#+TITLE: Weekend garden\n#+FILETAGS: :home:\n\n"
             "* TODO Plan the garden\nA few ideas for a slower Saturday.\n\n"
             "** Before breakfast\n- [X] Water the seedlings.\n- [ ] Sketch the garden beds.\n- [ ] Plant rosemary beside the path.\n\n"
             "** Notes\nThe afternoon light reaches the back fence.\nLeave room for the late summer flowers.\n\n"
             "** Next weekend\n- [ ] Visit the community garden.\n- [ ] Pick up compost on the way home.\n");
        NoteObject *reading = MakeNote(library, @"Reading list",
            @"#+TITLE: Reading list\n\n* TODO Read about garden design\n- [ ] A book about paths and quiet corners\n"
             "- [ ] An essay on careful observation\n\n** Ideas to keep\nBorrow a few ideas for the garden notebook.\n");
        NoteObject *trip = MakeNote(library, @"Trip checklist",
            @"#+TITLE: Trip checklist\n#+FILETAGS: :travel:\n\n"
             "* TODO Get ready for the trip\nKeep the plans light and leave room to explore.\n\n"
             "** Pack [2/4]\n- [X] Tickets and a notebook\n- [X] A small camera\n- [ ] A warm layer for the train\n- [ ] A book for the trip\n\n"
             "** Before leaving\n- [ ] Save the route\n- [ ] Water the garden before the trip\n\n"
             "** A useful reminder\nBring /less stuff/ and make *more memories*.\n");
        NoteObject *fieldNote = MakeNote(library, @"Field notes",
            @"#+TITLE: Field notes\n\n* TODO Collect a few ideas\n- [ ] Sketch a garden path in the notebook\n"
             "- [ ] Write down a thought before it disappears\n\n** Today\nKeep the tools quiet and the text close.\n");
        for (NoteObject *note in @[garden, reading, trip, fieldNote]) [note setSourceSyntaxIdentifier:@"org"];
