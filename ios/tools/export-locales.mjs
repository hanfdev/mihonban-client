import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const languages = ['en', 'ja', 'ko', 'fr', 'es', 'zh-Hans', 'zh-Hant']
const extra = {
  appearance: ["Appearance", "外観", "화면 모드", "Apparence", "Apariencia", "外观", "外觀"],
  appearanceSystem: ["Follow System", "システムに従う", "시스템 설정 따르기", "Selon le système", "Seguir el sistema", "跟随系统", "跟隨系統"],
  appearanceLight: ["Light", "ライト", "라이트", "Clair", "Claro", "浅色", "淺色"],
  appearanceDark: ["Dark", "ダーク", "다크", "Sombre", "Oscuro", "深色", "深色"],
  preloadOff: ["Off", "オフ", "끔", "Désactivé", "Desactivado", "关闭", "關閉"],
  preloadAutomatic: ["Automatic (Wi-Fi)", "自動（Wi-Fi）", "자동 (Wi-Fi)", "Automatique (Wi-Fi)", "Automático (Wi-Fi)", "自动（Wi-Fi）", "自動（Wi-Fi）"],
  preloadAlways: ["Always (including cellular)", "常にオン（モバイル通信を含む）", "항상 (모바일 데이터 포함)", "Toujours (données mobiles incluses)", "Siempre (incluye datos móviles)", "始终开启（含移动网络）", "一律開啟（含行動網路）"],
  preloadHint: ["Prepare only the next queued track. Automatic avoids cellular, metered connections and Low Data Mode. Always may use mobile data. This works even when the local cache is off.", "キューの次の1曲だけを先読みします。自動ではモバイル通信、従量制接続、低データモードを使いません。常にオンではモバイルデータを使用する場合があります。キャッシュを無効にしていても利用できます。", "대기열의 다음 한 곡만 미리 받습니다. 자동 모드에서는 모바일 데이터, 요금제 연결, 저데이터 모드를 사용하지 않습니다. 항상 모드에서는 모바일 데이터를 사용할 수 있습니다. 캐시가 꺼져 있어도 작동합니다.", "Prépare uniquement le prochain titre. Le mode automatique évite les données mobiles, les connexions limitées et le mode de données réduites. Toujours peut utiliser les données mobiles, même sans cache local.", "Prepara solo la siguiente canción. El modo automático evita datos móviles, conexiones medidas y el modo de datos reducidos. Siempre puede usar datos móviles. Funciona incluso sin caché local.", "仅提前准备队列中的下一首。自动模式避开移动网络、计费连接和低数据模式；始终开启可能消耗移动数据。关闭本地缓存时仍可使用。", "僅預先準備佇列中的下一首。自動模式避開行動網路、計費連線和低數據模式；一律開啟可能使用行動數據。關閉本機快取時仍可使用。"],
  shareAlbum: ["Share album", "アルバムを共有", "앨범 공유", "Partager l’album", "Compartir álbum", "分享音盘", "分享音盤"],
  shareTrack: ["Share song", "曲を共有", "곡 공유", "Partager le morceau", "Compartir canción", "分享歌曲", "分享歌曲"],
  searchTracks: ["Search songs in this list", "この一覧の曲を検索", "이 목록에서 곡 검색", "Rechercher dans ces morceaux", "Buscar canciones en esta lista", "搜索当前列表中的歌曲", "搜尋目前列表中的歌曲"],
  preparingQueue: ["Preparing queue…", "キューを準備中…", "대기열 준비 중…", "Préparation de la file…", "Preparando cola…", "正在准备队列…", "正在準備佇列…"],
  incompleteQueue: ["The complete queue could not be loaded. Refresh the library and try again.", "キュー全体を読み込めませんでした。ライブラリを更新して再試行してください。", "전체 대기열을 불러오지 못했습니다. 라이브러리를 새로 고친 후 다시 시도하세요.", "Impossible de charger toute la file. Actualisez la bibliothèque et réessayez.", "No se pudo cargar la cola completa. Actualiza la biblioteca e inténtalo de nuevo.", "未能载入完整队列，请刷新曲库后重试。", "無法載入完整佇列，請重新整理曲庫後再試。"],

  address: ['Service address', 'サーバーアドレス', '서버 주소', 'Adresse du service', 'Dirección del servicio', '服务地址', '服務位址'],
  connect: ['Connect', '接続', '연결', 'Connecter', 'Conectar', '连接', '連線'],
  connecting: ['Connecting…', '接続中…', '연결 중…', 'Connexion…', 'Conectando…', '正在连接…', '正在連線…'],
  connection: ['Service connection', 'サーバー接続', '서버 연결', 'Connexion au service', 'Conexión al servicio', '服务连接', '服務連線'],
  connectHint: ['Your collection, wherever you listen.', 'いつもの音楽を、どこでも。', '어디서든 나의 음악을.', 'Votre collection, partout avec vous.', 'Tu colección, donde quieras escuchar.', '随时随地，听自己的收藏。', '隨時隨地，聽自己的收藏。'],
  optionalPassword: ['Optional when guest access is enabled', 'ゲストアクセス有効時は省略可', '게스트 접속 시 생략 가능', 'Facultatif si l’accès invité est activé', 'Opcional si se permite acceso de invitados', '已开启访客访问时可留空', '已開啟訪客存取時可留空'],
  remember: ['Save password in Keychain', 'パスワードをキーチェーンに保存', '키체인에 비밀번호 저장', 'Enregistrer le mot de passe dans le trousseau', 'Guardar la contraseña en el llavero', '将口令保存在钥匙串', '將口令儲存於鑰匙圈'],
  settings: ['Settings', '設定', '설정', 'Réglages', 'Ajustes', '设置', '設定'],
  preparing: ['Buffering…', '読み込み中…', '버퍼링 중…', 'Mise en mémoire…', 'Cargando audio…', '正在缓冲…', '正在緩衝…'],
  nowPlaying: ['Now playing', '再生中', '지금 재생 중', 'À l’écoute', 'Reproduciendo', '正在播放', '正在播放'],
  queue: ['Queue', '再生キュー', '재생 대기열', 'File d’attente', 'Cola', '播放队列', '播放佇列'],
  upNext: ['Up next', '次に再生', '다음 곡', 'À suivre', 'A continuación', '接下来播放', '接下來播放'],
  collapse: ['Close player', 'プレーヤーを閉じる', '플레이어 닫기', 'Fermer le lecteur', 'Cerrar reproductor', '收起播放器', '收起播放器'],
  audioOutput: ['Audio output', '出力先', '오디오 출력', 'Sortie audio', 'Salida de audio', '音频输出', '音訊輸出'],
  expanded: ['Expanded', '展開済み', '펼쳐짐', 'Développé', 'Expandido', '已展开', '已展開'],
  collapsed: ['Collapsed', '折りたたみ', '접힘', 'Réduit', 'Contraído', '已收起', '已收起'],
  moreArtists: ['+{0} more', 'ほか{0}組', '외 {0}명', '+{0} autres', '+{0} más', '另 {0} 位', '另 {0} 位'],
  viewCredits: ['View full artist credits', 'アーティストの全クレジットを表示', '전체 아티스트 크레딧 보기', 'Voir tous les artistes crédités', 'Ver todos los artistas acreditados', '查看完整艺人署名', '查看完整藝人署名'],
  fullTitle: ['Full track title', '曲名を全文表示', '전체 곡 제목', 'Titre complet du morceau', 'Título completo de la pista', '完整曲名', '完整曲名'],
  viewArtist: ['View artist', 'アーティストを表示', '아티스트 보기', 'Voir l’artiste', 'Ver artista', '查看艺人', '查看藝人'],
  searchAlbums: ['Search albums and artists', 'アルバム・アーティストを検索', '앨범과 아티스트 검색', 'Rechercher des albums et artistes', 'Buscar álbumes y artistas', '搜索专辑与艺人', '搜尋專輯與藝人'],
  invalidAddress: ['Enter a full http:// or https:// address.', 'http:// または https:// で始まるアドレスを入力してください。', 'http:// 또는 https://로 시작하는 주소를 입력하세요.', 'Saisissez une adresse complète en http:// ou https://.', 'Introduce una dirección completa con http:// o https://.', '请输入以 http:// 或 https:// 开头的完整地址。', '請輸入以 http:// 或 https:// 開頭的完整位址。'],
  connectionFailed: ['Could not reach the service. Check the address and connection, then try again.', 'サーバーに接続できません。アドレスと通信状況を確認してください。', '서버에 연결할 수 없습니다. 주소와 연결 상태를 확인하세요.', 'Service inaccessible. Vérifiez l’adresse et la connexion, puis réessayez.', 'No se pudo conectar. Comprueba la dirección y la conexión e inténtalo de nuevo.', '无法连接服务，请检查地址和网络后重试。', '無法連線至服務，請檢查位址與網路後重試。'],
  wrongPassword: ['Incorrect password.', 'パスワードが違います。', '비밀번호가 올바르지 않습니다.', 'Mot de passe incorrect.', 'Contraseña incorrecta.', '口令不正确。', '口令不正確。'],
  sessionExpired: ['Sign in with your service password.', 'サーバーのパスワードでログインしてください。', '서버 비밀번호로 로그인하세요.', 'Connectez-vous avec le mot de passe du service.', 'Inicia sesión con la contraseña del servicio.', '请使用服务口令登录。', '請使用服務口令登入。'],
  rateLimited: ['Too many attempts. Try again in 15 minutes.', '試行回数が多すぎます。15 分後にお試しください。', '시도 횟수가 너무 많습니다. 15분 후 다시 시도하세요.', 'Trop de tentatives. Réessayez dans 15 minutes.', 'Demasiados intentos. Vuelve a intentarlo en 15 minutos.', '尝试过于频繁，请在 15 分钟后重试。', '嘗試過於頻繁，請在 15 分鐘後重試。'],
  playbackFailed: ['Could not play this track. Check your connection or try the next track.', 'この曲を再生できません。接続を確認するか、次の曲をお試しください。', '재생할 수 없습니다. 연결을 확인하거나 다음 곡을 재생하세요.', 'Lecture impossible. Vérifiez la connexion ou essayez la piste suivante.', 'No se puede reproducir. Comprueba la conexión o prueba la siguiente pista.', '无法播放这首曲目，请检查网络或尝试下一首。', '無法播放這首曲目，請檢查網路或嘗試下一首。'],
  seekFailed: ['Couldn’t change the playback position. Please try again.', '再生位置を変更できませんでした。もう一度お試しください。', '재생 위치를 변경하지 못했습니다. 다시 시도해 주세요.', 'Impossible de changer la position de lecture. Réessayez.', 'No se pudo cambiar la posición de reproducción. Inténtalo de nuevo.', '暂时无法跳转到该位置，请重试。', '暫時無法跳轉到該位置，請重試。'],
  audioReset: ['Audio was interrupted by the system. Select a track to resume.', 'システムにより音声が停止しました。曲を選んで再開してください。', '시스템이 오디오를 중단했습니다. 곡을 선택해 다시 재생하세요.', 'Le système a interrompu l’audio. Sélectionnez une piste pour reprendre.', 'El sistema interrumpió el audio. Selecciona una pista para continuar.', '系统重置了音频服务，请重新选择曲目播放。', '系統重設了音訊服務，請重新選擇曲目播放。'],
  keychainFailed: ['Connected, but the password could not be saved. Sign in again after restarting.', '接続しましたが、パスワードを保存できませんでした。再起動後に再ログインしてください。', '연결했지만 비밀번호를 저장하지 못했습니다. 재시작 후 다시 로그인하세요.', 'Connexion établie, mais le mot de passe n’a pas été enregistré. Reconnectez-vous après redémarrage.', 'Conectado, pero no se pudo guardar la contraseña. Inicia sesión tras reiniciar.', '连接成功，但口令未能保存，重启后需要重新登录。', '連線成功，但口令未能儲存，重新啟動後需要再次登入。'],
  insecureHTTP: ['HTTP does not encrypt your password or audio. Use HTTPS outside a trusted network.', 'HTTP はパスワードや音声を暗号化しません。信頼できないネットワークでは HTTPS を使ってください。', 'HTTP는 비밀번호와 오디오를 암호화하지 않습니다. 외부 네트워크에서는 HTTPS를 사용하세요.', 'HTTP ne chiffre ni le mot de passe ni l’audio. Utilisez HTTPS hors d’un réseau de confiance.', 'HTTP no cifra tu contraseña ni el audio. Usa HTTPS fuera de una red de confianza.', 'HTTP 不会加密口令或音频；在可信网络之外请使用 HTTPS。', 'HTTP 不會加密口令或音訊；在可信網路之外請使用 HTTPS。'],
  m0Notice: ['Preview: library, playback, lock-screen controls and offline downloads. Library management is still on the web.', 'プレビュー：ライブラリ、再生、ロック画面操作、オフライン保存。ライブラリ管理は引き続きWebで行います。', '미리보기: 보관함, 재생, 잠금 화면 제어, 오프라인 다운로드. 보관함 관리는 아직 웹에서 합니다.', 'Aperçu : bibliothèque, lecture, commandes sur écran verrouillé et téléchargements hors ligne. La gestion de la bibliothèque reste sur le web.', 'Vista previa: biblioteca, reproducción, controles en pantalla bloqueada y descargas sin conexión. La gestión de la biblioteca sigue en la web.', '预览版：曲库、播放、锁屏控制与离线下载。曲库管理仍在网页端进行。', '預覽版：曲庫、播放、鎖定畫面控制與離線下載。曲庫管理仍在網頁端進行。'],
  prefetchNotice: ['The next track is preloaded only on an unmetered connection without Low Data Mode.', '次の曲の先読みは、低データモードでない従量制限のない接続でのみ行います。', '다음 곡은 저데이터 모드가 아닌 무제한 연결에서만 미리 받습니다.', 'Préchargement uniquement sur une connexion non limitée, sans mode de données réduites.', 'Precarga solo con conexión no medida y sin modo de datos reducidos.', '仅在非计费且未开启低数据模式的网络下预取下一首。', '僅在非計費且未開啟低數據模式的網路下預取下一首。'],
  cache: ['Local cache', 'ローカルキャッシュ', '로컬 캐시', 'Cache local', 'Caché local', '本地缓存', '本機快取'],
  cacheEnable: ['Cache covers and audio on this iPhone', 'カバーと音声をこの iPhone に保存', '커버와 오디오를 이 iPhone에 저장', 'Conserver pochettes et audio sur cet iPhone', 'Guardar carátulas y audio en este iPhone', '在本机缓存封面和音频', '在本機快取封面與音訊'],
  cacheHint: ['Cached tracks start instantly and keep playing offline. The oldest files are removed once the limit is reached.', 'キャッシュした曲はすぐに再生でき、オフラインでも聴けます。上限に達すると古いファイルから削除されます。', '캐시된 곡은 즉시 재생되고 오프라인에서도 재생됩니다. 한도에 도달하면 오래된 파일부터 삭제합니다.', 'Les titres en cache démarrent instantanément et restent lisibles hors connexion. Les fichiers les plus anciens sont supprimés à la limite.', 'Las pistas en caché empiezan al instante y siguen sonando sin conexión. Al alcanzar el límite se eliminan los archivos más antiguos.', '缓存的曲目可立即起播，离线也能继续听；达到上限后从最旧的文件开始清理。', '快取的曲目可立即起播，離線也能繼續聽；達到上限後從最舊的檔案開始清理。'],
  cacheOffNotice: ['Caching is off. Audio streams while you listen and is discarded afterwards.', 'キャッシュは無効です。音声は再生中にストリーミングされ、終了後に破棄されます。', '캐시가 꺼져 있습니다. 오디오는 재생 중 스트리밍되고 끝나면 삭제됩니다.', 'Cache désactivé : l’audio est diffusé pendant l’écoute puis supprimé.', 'Caché desactivada: el audio se transmite mientras escuchas y se descarta después.', '缓存已关闭：音频边听边传，听完即丢弃。', '快取已關閉：音訊邊聽邊傳，聽完即丟棄。'],
  cacheLimit: ['Size limit', '容量上限', '용량 한도', 'Taille maximale', 'Tamaño máximo', '大小上限', '容量上限'],
  cacheUsed: ['Used', '使用中', '사용 중', 'Utilisé', 'Utilizado', '已使用', '已使用'],
  clearCache: ['Clear cache', 'キャッシュを消去', '캐시 비우기', 'Vider le cache', 'Vaciar caché', '清除缓存', '清除快取'],
  cacheCleared: ['Cache cleared', 'キャッシュを消去しました', '캐시를 비웠습니다', 'Cache vidé', 'Caché vaciada', '缓存已清除', '快取已清除'],
  preloadNext: ['Preload the next queued track', '次のキュー曲を先読みする', '대기열의 다음 곡 미리 받기', 'Précharger le prochain titre', 'Precargar la siguiente canción', '预加载下一首歌曲', '預先載入下一首歌曲'],
  disconnectConfirm: ['Stop playback and sign out?', '再生を停止してログアウトしますか？', '재생을 중지하고 로그아웃할까요?', 'Arrêter la lecture et se déconnecter ?', '¿Detener la reproducción y cerrar sesión?', '停止播放并退出登录？', '停止播放並登出？'],
  permissionDenied: ['Your account cannot perform this action.', 'この操作は許可されていません。', '이 작업을 수행할 권한이 없습니다.', 'Votre compte ne permet pas cette action.', 'Tu cuenta no permite esta acción.', '当前账号没有此操作的权限。', '目前帳號沒有此操作的權限。'],
  itemMissing: ['This item is no longer available.', 'この項目は利用できなくなりました。', '이 항목은 더 이상 사용할 수 없습니다.', 'Cet élément n’est plus disponible.', 'Este elemento ya no está disponible.', '此项目已不可用。', '此項目已無法使用。'],
  conflict: ['The library changed. Refresh and try again.', 'ライブラリが変更されました。更新して再試行してください。', '보관함이 변경되었습니다. 새로고침 후 다시 시도하세요.', 'La bibliothèque a changé. Actualisez puis réessayez.', 'La biblioteca ha cambiado. Actualiza e inténtalo de nuevo.', '曲库已发生变化，请刷新后重试。', '曲庫已發生變更，請重新整理後再試。'],
  downloads: ['Downloads', 'ダウンロード', '다운로드', 'Téléchargements', 'Descargas', '下载', '下載'],
  download: ['Download', 'ダウンロード', '다운로드', 'Télécharger', 'Descargar', '下载', '下載'],
  playNext: ['Play next', '次に再生', '다음에 재생', 'Lire ensuite', 'Reproducir a continuación', '下一首播放', '下一首播放'],
  addToQueue: ['Add to queue', 'キューに追加', '대기열에 추가', 'Ajouter à la file', 'Añadir a la cola', '加入播放队列', '加入播放佇列'],
  allResults: ['All', 'すべて', '전체', 'Tout', 'Todo', '全部', '全部'],
  filters: ['Filters', '絞り込み', '필터', 'Filtres', 'Filtros', '筛选', '篩選'],
  sort: ['Sort', '並べ替え', '정렬', 'Trier', 'Ordenar', '排序', '排序'],
  downloaded: ['Downloaded', 'ダウンロード済み', '다운로드됨', 'Téléchargé', 'Descargado', '已下载', '已下載'],
  removeDownload: ['Remove download', 'ダウンロードを削除', '다운로드 삭제', 'Supprimer le téléchargement', 'Eliminar descarga', '删除下载', '刪除下載'],
  removeDownloadConfirm: ['Remove the downloaded files of this album from this iPhone?', 'このアルバムのダウンロード済みファイルを iPhone から削除しますか？', '이 앨범의 다운로드한 파일을 iPhone에서 삭제할까요?', 'Supprimer de cet iPhone les fichiers téléchargés de cet album ?', '¿Eliminar de este iPhone los archivos descargados de este álbum?', '要从本机删除这张专辑已下载的文件吗？', '要從本機刪除這張專輯已下載的檔案嗎？'],
  removeAllDownloads: ['Remove all downloads', 'すべてのダウンロードを削除', '모든 다운로드 삭제', 'Supprimer tous les téléchargements', 'Eliminar todas las descargas', '删除全部下载', '刪除全部下載'],
  removeAllConfirm: ['Remove every downloaded track from this iPhone?', 'ダウンロードしたすべての曲を iPhone から削除しますか？', '다운로드한 모든 곡을 iPhone에서 삭제할까요?', 'Supprimer de cet iPhone tous les titres téléchargés ?', '¿Eliminar de este iPhone todas las pistas descargadas?', '要从本机删除全部已下载的曲目吗？', '要從本機刪除全部已下載的曲目嗎？'],
  downloadQueued: ['Waiting', '待機中', '대기 중', 'En attente', 'En espera', '等待中', '等待中'],
  downloadFailed: ['Download failed', 'ダウンロードに失敗しました', '다운로드 실패', 'Échec du téléchargement', 'Error en la descarga', '下载失败', '下載失敗'],
  downloadInterrupted: ['Stopped before finishing', '完了前に停止しました', '완료 전에 중지됨', 'Arrêté avant la fin', 'Detenida antes de terminar', '未完成即中止', '未完成即中止'],
  downloadInterruptedHint: ['Downloads continue while the app is in the background, but closing it from the app switcher stops them. Try again to resume.', 'アプリがバックグラウンドでもダウンロードは続きますが、App スイッチャーで終了すると停止します。再試行すると再開します。', '앱이 백그라운드에 있어도 다운로드는 계속되지만, 앱 전환기에서 종료하면 중지됩니다. 다시 시도하면 재개됩니다.', 'Les téléchargements continuent en arrière-plan, mais fermer l’app depuis le sélecteur les arrête. Réessayez pour reprendre.', 'Las descargas siguen en segundo plano, pero cerrar la app desde el selector las detiene. Vuelve a intentarlo para reanudar.', '应用在后台时下载会继续，但从多任务界面划掉应用会使其中止；重试即可继续。', 'App 在背景時下載會繼續，但從多工畫面滑掉 App 會使其中止；重試即可繼續。'],
  retryAll: ['Retry all', 'すべて再試行', '모두 다시 시도', 'Tout réessayer', 'Reintentar todo', '全部重试', '全部重試'],
  downloadsEmpty: ['No downloads', 'ダウンロードはありません', '다운로드 없음', 'Aucun téléchargement', 'Sin descargas', '暂无下载', '尚無下載'],
  downloadsEmptyHint: ['Download an album from its page. Downloaded tracks play from this iPhone without streaming.', 'アルバムのページからダウンロードできます。ダウンロードした曲はストリーミングせずに再生されます。', '앨범 페이지에서 다운로드할 수 있습니다. 다운로드한 곡은 스트리밍 없이 재생됩니다.', 'Téléchargez un album depuis sa page. Les titres téléchargés sont lus depuis cet iPhone, sans streaming.', 'Descarga un álbum desde su página. Las pistas descargadas se reproducen desde este iPhone sin streaming.', '可在专辑页下载。已下载的曲目直接从本机播放，无需在线传输。', '可在專輯頁下載。已下載的曲目直接從本機播放，無需線上傳輸。'],
  downloadsHint: ['Downloads are kept until you remove them. Clearing the cache does not affect them.', 'ダウンロードは削除するまで保持され、キャッシュを消去しても残ります。', '다운로드는 직접 삭제할 때까지 유지되며 캐시를 비워도 남습니다.', 'Les téléchargements sont conservés jusqu’à leur suppression ; vider le cache ne les touche pas.', 'Las descargas se conservan hasta que las elimines; vaciar la caché no las afecta.', '下载内容会一直保留，直到手动删除；清除缓存不影响下载。', '下載內容會一直保留，直到手動刪除；清除快取不影響下載。'],
  cacheAudio: ['Audio', '音声', '오디오', 'Audio', 'Audio', '音频', '音訊'],
  cacheCovers: ['Covers', 'カバー', '커버', 'Pochettes', 'Carátulas', '封面', '封面'],
  cacheBuffer: ['Playing now (temporary)', '再生中（一時ファイル）', '재생 중(임시)', 'Lecture en cours (temporaire)', 'En reproducción (temporal)', '正在播放（临时）', '正在播放（暫存）'],
  cacheClearFailed: ['Some cached files could not be removed. Try again.', '一部のキャッシュを削除できませんでした。もう一度お試しください。', '일부 캐시 파일을 삭제하지 못했습니다. 다시 시도하세요.', 'Certains fichiers du cache n’ont pas pu être supprimés. Réessayez.', 'No se pudieron eliminar algunos archivos de la caché. Inténtalo de nuevo.', '部分缓存文件未能删除，请重试。', '部分快取檔案未能刪除，請重試。'],
  offlineLibrary: ['The service is unreachable. Showing the library saved on this device; downloads still play.', 'サーバーに接続できません。この端末に保存したライブラリを表示しています。ダウンロード済みの曲は再生できます。', '서버에 연결할 수 없습니다. 이 기기에 저장된 보관함을 표시하며, 다운로드한 곡은 재생할 수 있습니다.', 'Service inaccessible. Affichage de la bibliothèque enregistrée sur cet appareil ; les téléchargements restent lisibles.', 'No se puede conectar. Se muestra la biblioteca guardada en este dispositivo; las descargas se pueden reproducir.', '无法连接服务，正在显示本机保存的曲库，已下载的曲目仍可播放。', '無法連線至服務，正在顯示本機儲存的曲庫，已下載的曲目仍可播放。'],
  listSeparatorHint: ['Separate entries with semicolons or commas.', '項目はセミコロンまたはカンマで区切ります。', '항목은 세미콜론이나 쉼표로 구분합니다.', 'Séparez les éléments par des points-virgules ou des virgules.', 'Separa los elementos con punto y coma o comas.', '多个条目用分号或逗号分隔。', '多個項目以分號或逗號分隔。'],
  inputRejected: ['The service rejected this input. Check the fields and try again.', 'サーバーがこの入力を受け付けませんでした。項目を確認してもう一度お試しください。', '서버가 이 입력을 거부했습니다. 항목을 확인한 뒤 다시 시도하세요.', 'Le service a refusé cette saisie. Vérifiez les champs et réessayez.', 'El servicio rechazó estos datos. Revisa los campos e inténtalo de nuevo.', '服务拒绝了这些内容，请检查各项后重试。', '服務拒絕了這些內容，請檢查各欄後重試。'],
  oneTrack: ['1 track', '1 曲', '1 곡', '1 titre', '1 pista', '1 曲', '1 曲'],
  oneAlbum: ['1 album', '1 音盤', '앨범 1', '1 album', '1 álbum', '1 音盤', '1 音盤'],
  manage: ['Manage', '管理', '관리', 'Gestion', 'Administrar', '管理', '管理'],
  moreActions: ['More actions', 'その他の操作', '더 많은 작업', 'Plus d’actions', 'Más acciones', '更多操作', '更多操作'],
  licenses: ['Open-source licenses', 'オープンソースライセンス', '오픈 소스 라이선스', 'Licences libres', 'Licencias de código abierto', '开源许可', '開源授權'],
}
const { en } = await import('../../cloud/web/src/locales/en.js')
const { adminEn } = await import('../../cloud/web/src/i18n-admin-en.js')
const catalogs = {}
const personal = JSON.parse(fs.readFileSync(path.join(root, 'tools/personal-locales.json'), 'utf8'))
function flatten(base, translated, prefix = '', result = {}) {
  for (const [name, fallback] of Object.entries(base)) {
    const key = prefix ? `${prefix}.${name}` : name
    const value = translated?.[name] ?? fallback
    if (typeof fallback === 'function') {
      result[key] = value('{0}', '{1}', '{2}', '{3}')
    } else if (typeof fallback === 'object' && fallback !== null) {
      flatten(fallback, value, key, result)
    } else if (typeof value === 'string') result[key] = value
  }
  return result
}
for (const [index, language] of languages.entries()) {
  const web = language === 'en' ? en : (await import(`../../cloud/web/src/locales/${language}.js`)).default
  const admin = language === 'en' ? adminEn : (await import(`../../cloud/web/src/locales/admin-${language}.js`)).admin
  const result = flatten(en, web)
  flatten(adminEn, admin, 'admin', result)
  for (const [key, values] of Object.entries(extra)) {
    if (values.length !== languages.length || values.some(value => !value)) throw new Error(`Incomplete translation: ${key}`)
    result['mobile.' + key] = values[index]
  }
  for (const [key, values] of Object.entries(personal)) {
    if (values.length !== languages.length || values.some(value => !value)) throw new Error(`Incomplete personal translation: ${key}`)
    result['personal.' + key] = values[index]
  }
  // Normalize only the album term in Simplified Chinese, preserving proper names.
  if (language === 'zh-Hans') {
    for (const key of Object.keys(result)) result[key] = result[key].replaceAll('音盤', '音盘')
  }
  catalogs[language] = result
}
fs.mkdirSync(path.join(root, 'Resources'), { recursive: true })
fs.writeFileSync(path.join(root, 'Resources/Localizations.json'), JSON.stringify(catalogs, null, 2) + '\n')
console.log(`Exported ${languages.length} iOS catalogs`)
