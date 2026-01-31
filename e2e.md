# Invader Dashboard E2E Tests

Test the dashboard at `http://localhost:4000`

## Sprites

### Sync sprites from API
1. Click "SYNC" button in Sprites section
2. Verify sprites appear in the list (or error flash if no token)

### Create sprite
1. Click "+ NEW SPRITE"
2. Fill in name (required), optionally org
3. Click CREATE
4. Verify sprite appears in list

### Edit sprite
1. Click a sprite row
2. Modal opens with current values
3. Change the name
4. Click UPDATE
5. Verify name changed in list

### Delete sprite
1. Click a sprite row to edit
2. Click DELETE button
3. Confirm deletion
4. Verify sprite removed from list

## Missions

### Create mission with file path
1. Click "+ NEW MISSION"
2. Select a sprite from dropdown
3. Keep "FILE PATH" mode selected
4. Enter a path like `/tmp/PROMPT.md`
5. Set priority and max waves
6. Click CREATE
7. Verify mission appears in list

### Create mission with inline prompt
1. Click "+ NEW MISSION"
2. Select a sprite
3. Click "INLINE PROMPT" toggle
4. Type prompt text in textarea
5. Click CREATE
6. Verify mission appears

### Edit pending mission
1. Click a pending mission row
2. Change priority or max waves
3. Click UPDATE
4. Verify changes persist

### View mission details
1. Click a mission row
2. See mission details modal
3. Check waves list if any exist

### Mission validation
1. Try creating mission without selecting sprite - should fail
2. Try creating mission with neither path nor prompt - should fail

## Saves

### View save details
1. Click a save row
2. See save details with checkpoint info

### Restore save
1. Click a save row
2. Click RESTORE button
3. Verify restore action triggers

### Delete save
1. Click a save row
2. Click DELETE
3. Confirm deletion
4. Verify save removed

## General UI

### Modal behavior
- ESC key closes modals
- Clicking outside modal closes it
- CANCEL button returns to dashboard

### Flash messages
- Success actions show green flash
- Errors show red flash
- Flashes auto-dismiss

### Real-time updates
- Dashboard updates when data changes
- No page refresh needed
