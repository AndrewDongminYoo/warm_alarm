-- No coordinates, no settings changes, no permission requests.
on run argv
  set bundleID to item 1 of argv
  set operation to item 2 of argv
  set buttonLabel to ""
  if (count argv) > 2 then set buttonLabel to item 3 of argv
  tell application "System Events"
    set candidates to every application process whose bundle identifier is bundleID
    if (count candidates) is not 1 then error "Expected one running process for " & bundleID
    set targetProcess to item 1 of candidates
    tell targetProcess
      if (count windows) is 0 then error "Target has no accessible window"
      if operation is "focus" then
        set frontmost to true
        perform action "AXRaise" of window 1
        return "Focused " & bundleID
      end if
      set nodes to entire contents of window 1
      set matches to {}
      set labels to {}
      repeat with node in nodes
        try
          if role of node is "AXButton" then
            set matched to false
            repeat with attributeName in {"AXTitle", "AXDescription", "AXValue"}
              try
                set labelValue to value of attribute (contents of attributeName) of node
                if class of labelValue is text and labelValue is not "" then
                  set end of labels to labelValue
                  if labelValue is buttonLabel then set matched to true
                end if
              end try
            end repeat
            if matched then set end of matches to contents of node
          end if
        end try
      end repeat
      if operation is "inspect" then return labels
      if operation is not "press" then error "Unknown operation"
      if (count matches) is not 1 then error "Expected one AXButton for: " & buttonLabel & ". Inspect accessibility labels before retrying."
      set targetButton to item 1 of matches
      if not enabled of targetButton then error "Button disabled: " & buttonLabel
      perform action "AXPress" of targetButton
      return "Pressed " & buttonLabel
    end tell
  end tell
end run
