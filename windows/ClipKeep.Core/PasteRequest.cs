namespace ClipKeep.Core;

public readonly record struct PasteRequest(long Generation, uint ClipboardSequence, nint Target)
{
    public bool CanSend(long currentGeneration, uint currentSequence, nint foreground, bool modifiersHeld)
        => Target != 0 && Generation == currentGeneration && ClipboardSequence == currentSequence
            && Target == foreground && !modifiersHeld;
}
