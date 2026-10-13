# MLBB Neural Coach

Нативное iOS-приложение в отдельной папке Racingtest. Исходники гонки и Android workflow сохранены.

Первый этап: минимальное SwiftUI-приложение и сборка неподписанного IPA. ИИ, память, анализ видео и голос пока не реализованы.

Actions / MLBB Coach unsigned IPA автоматически собирает pull request при изменении проекта. После объединения также собирает push в main и допускает ручной запуск. До объединения запуск выполняется через PR.

macos-26: проверка проекта, xcodebuild archive без сертификатов, упаковка Payload/MLBBNeuralCoach.app и публикация артефакта MLBBNeuralCoach-unsigned. В нём находятся IPA и SHA256SUMS.txt. Журнал ошибок и xcresult публикуются в build-diagnostics. Локальный Xcode не нужен.

IPA не подписан. Установка требует подписи своим Apple ID, например через Sideloadly. Бесплатная подпись обычно действует 7 дней. Установка на iPhone Air ещё не проверялась.

Deployment target iOS 26, совместимость с iOS 27. Реализация ScreenCaptureKit на iOS потребует SDK 27 на следующем этапе.

Полные требования: docs/REQUIREMENTS.md. Проверенные API: docs/FEASIBILITY.md. Локальные проверки: docs/VALIDATION.md.
