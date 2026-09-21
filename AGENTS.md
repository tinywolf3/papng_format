# PAPNG 개발 지침

- 포맷의 기준은 `spec/PAPNG-1.0.ko.md`이며 영어판은 번역본이다.
- 작업 전에 `.cursor/rules/build-output.mdc`의 공통 빌드 출력 정책을 적용한다.
- 명세 HTML을 생성하지 않는다. 웹 뷰어의 앱 진입점인 HTML은 이 제한의 대상이 아니다.
- 포맷 변경 없이 구현을 추가할 때 명세 버전이나 문서 개정을 올리지 않는다.
- 사용자 공통 Git 정책에 따라 `codex/*` 브랜치에서 작업하고 검증한 변경만 커밋한다.
- TypeScript 변경은 `npm run check`, 뷰어 변경은 추가로 `npm run build`와 `npm run test:web`로 검증한다.
- 샘플 변경 시 생성기를 함께 수정하고 `npm run samples`의 재현성을 확인한다.
