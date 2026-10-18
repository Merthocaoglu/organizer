import 'package:flutter/material.dart';

import '../services/event_store.dart';
import '../services/quiz_store.dart';
import '../widgets/add_event_sheet.dart';
import 'quiz_screen.dart';
import 'stats_screen.dart';
import '../widgets/day_view.dart';
import '../widgets/month_view.dart';
import '../widgets/week_view.dart';
import '../widgets/year_view.dart';

enum CalendarView { day, week, month, year }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, required this.quiz});

  final EventStore store;
  final QuizStore quiz;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CalendarView _view = CalendarView.day;
  DateTime _selectedDate = DateTime.now();

  void _setDate(DateTime date) => setState(() => _selectedDate = date);

  void _openDay(DateTime date) => setState(() {
        _selectedDate = date;
        _view = CalendarView.day;
      });

  void _openMonth(DateTime date) => setState(() {
        _selectedDate = date;
        _view = CalendarView.month;
      });

  Future<void> _addEvent() => showEventSheet(
        context,
        store: widget.store,
        date: _selectedDate,
        onSaved: _openDay,
      );

  Widget _buildView() {
    switch (_view) {
      case CalendarView.day:
        return DayView(
          store: widget.store,
          date: _selectedDate,
          onDateChanged: _setDate,
        );
      case CalendarView.week:
        return WeekView(
          store: widget.store,
          date: _selectedDate,
          onDateChanged: _setDate,
          onDayTap: _openDay,
        );
      case CalendarView.month:
        return MonthView(
          store: widget.store,
          date: _selectedDate,
          onDateChanged: _setDate,
          onDayTap: _openDay,
        );
      case CalendarView.year:
        return YearView(
          store: widget.store,
          date: _selectedDate,
          onDateChanged: _setDate,
          onMonthTap: _openMonth,
          onDayTap: _openDay,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Organizer'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.quiz_outlined),
            tooltip: 'Daily quiz',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => QuizScreen(store: widget.quiz),
            )),
          ),
          IconButton(
            icon: const Icon(Icons.insights),
            tooltip: 'Analysis',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  StatsScreen(store: widget.store, date: _selectedDate),
            )),
          ),
          TextButton(
            onPressed: () => _openDay(DateTime.now()),
            child: const Text('Today'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SegmentedButton<CalendarView>(
              segments: const [
                ButtonSegment(value: CalendarView.day, label: Text('Day')),
                ButtonSegment(value: CalendarView.week, label: Text('Week')),
                ButtonSegment(value: CalendarView.month, label: Text('Month')),
                ButtonSegment(value: CalendarView.year, label: Text('Year')),
              ],
              selected: {_view},
              onSelectionChanged: (selection) =>
                  setState(() => _view = selection.first),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.store,
              builder: (context, _) => _buildView(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEvent,
        tooltip: 'Add event',
        child: const Icon(Icons.add),
      ),
    );
  }
}
