import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/event.dart';
import '../services/event_store.dart';
import 'add_event_sheet.dart';

/// Details dialog for an event — info plus Edit and Delete (with Undo).
/// Used by the Day timeline bubbles and the Week grid chips.
void showEventDetailsDialog(
  BuildContext context, {
  required EventStore store,
  required Event event,
}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          CircleAvatar(backgroundColor: event.category.color, radius: 6),
          const SizedBox(width: 8),
          Expanded(child: Text(event.title)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${event.start.format(context)} – ${event.end.format(context)}'
            '${event.isOvernight ? ' (next day)' : ''}'
            '  ·  ${event.category.label}',
          ),
          if (event.repeatsWeekly)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Repeats every ${DateFormat('EEEE').format(event.date)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary),
              ),
            ),
          if (event.reminderMinutes != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                event.reminderMinutes == 0
                    ? 'Reminder at start time'
                    : 'Reminder ${event.reminderMinutes} min before',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary),
              ),
            ),
          if (event.notes != null) ...[
            const SizedBox(height: 12),
            Text(event.notes!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            showEventSheet(
              context,
              store: store,
              date: event.date,
              existing: event,
            );
          },
          child: const Text('Edit'),
        ),
        FilledButton.tonal(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            store.remove(event);
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                content: Text(event.repeatsWeekly
                    ? 'Deleted "${event.title}" (all weeks)'
                    : 'Deleted "${event.title}"'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () => store.add(
                    date: event.date,
                    start: event.start,
                    end: event.end,
                    title: event.title,
                    category: event.category,
                    notes: event.notes,
                    repeatsWeekly: event.repeatsWeekly,
                    reminderMinutes: event.reminderMinutes,
                  ),
                ),
              ));
          },
          child: Text(event.repeatsWeekly ? 'Delete all' : 'Delete'),
        ),
      ],
    ),
  );
}
