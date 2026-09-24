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
            @"#+TITLE: Field notes\n#+FILETAGS: :notebook:\n\n"
             "* TODO Capture the small things\nA small place for ideas, plans, and things worth keeping.\n\n"
             "** Today [1/3]\n- [X] Write down *ideas* while they are fresh.\n"
             "- [ ] Find a thought with a few remembered words.\n- [ ] Leave room for something unexpected.\n\n"
             "** Reading notes\nKeep /useful passages/ and =exact words= close to hand.\n"
             "[[https://orgmode.org][Org mode documentation]]\n\n"
             "** A little structure\n| Topic   | Next step        |\n|---------+------------------|\n"
             "| Garden  | Plant rosemary   |\n| Reading | Start a new book |\n\n"
             "#+BEGIN_SRC json\n{\"topic\": \"ideas\", \"status\": \"growing\"}\n#+END_SRC\n");
        for (NoteObject *note in @[garden, reading, trip, fieldNote]) [note setSourceSyntaxIdentifier:@"org"];
