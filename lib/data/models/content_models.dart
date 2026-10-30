class ContentModule {
  final String id, title;
  const ContentModule({required this.id, required this.title});
}

class ContentLesson {
  final String id, title, kind, moduleId;
  final Map<String, dynamic> data;
  const ContentLesson({
    required this.id,
    required this.title,
    required this.kind,
    required this.moduleId,
    required this.data,
  });
  factory ContentLesson.fromJson(Map<String, dynamic> row) => ContentLesson(
    id: row['id'] as String,
    title: row['title'] as String,
    kind: row['kind'] as String,
    moduleId: row['module_id'] as String,
    data: row,
  );
}

const lessonTypeLabels = {
  'video': 'Vídeo',
  'audio': 'Áudio',
  'pdf': 'PDF',
  'reading': 'Leitura',
  'quiz': 'Quiz',
  'animation': 'Imagem / Animação',
};
