# chore(hooks,constructs): allow bounded hidden dirs, first-match local sources, strict traversal rejection

Lets recursive deletes target bounded hidden subdirectories through a named exclusion list, returns the first existing local source path in find_local_source, and rejects any construct link or target containing a dot-dot segment.
