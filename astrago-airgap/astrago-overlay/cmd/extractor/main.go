package main

import (
	"fmt"
	"os"
	"time"

	"github.com/astrago/helm-image-extractor/internal/config"
	"github.com/astrago/helm-image-extractor/internal/discovery"
	"github.com/astrago/helm-image-extractor/internal/extractor"
	"github.com/astrago/helm-image-extractor/internal/output"
	"github.com/astrago/helm-image-extractor/internal/renderer"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
	"github.com/spf13/cobra"
)

var (
	version = "dev"
	commit  = "none"
	date    = "unknown"
)

func main() {
	// Configure zerolog
	log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stderr})

	rootCmd := &cobra.Command{
		Use:   "extract-images",
		Short: "Astrago Helm Chart 이미지 추출기",
		Long: `Helm 차트에서 컨테이너 이미지를 자동으로 추출하여
오프라인 Kubernetes 배포를 위한 이미지 목록을 생성합니다.`,
		Version: fmt.Sprintf("%s (commit: %s, built: %s)", version, commit, date),
		RunE:    run,
	}

	// 플래그 정의
	rootCmd.Flags().StringP("helmfile", "f", "", "Helmfile 경로 (기본: 자동 탐색)")
	rootCmd.Flags().StringP("environment", "e", "default", "Helmfile 환경")
	rootCmd.Flags().StringP("output", "o", "", "출력 파일 (기본: kubespray-offline/imagelists/astrago.txt)")
	rootCmd.Flags().StringP("format", "F", "text", "출력 형식 (text|json|yaml)")
	rootCmd.Flags().IntP("workers", "w", 5, "병렬 처리 워커 수")
	rootCmd.Flags().BoolP("verbose", "v", false, "상세 출력")
	rootCmd.Flags().Bool("debug", false, "디버그 모드")
	rootCmd.Flags().Bool("generate-script", false, "다운로드 스크립트 생성")
	rootCmd.Flags().Bool("generate-report", false, "상세 리포트 생성")

	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func run(cmd *cobra.Command, args []string) error {
	startTime := time.Now()

	// 1. 설정 로드
	cfg, err := config.Load(cmd)
	if err != nil {
		return fmt.Errorf("설정 로드 실패: %w", err)
	}

	// 로그 레벨 설정
	if cfg.Debug {
		zerolog.SetGlobalLevel(zerolog.DebugLevel)
	} else if cfg.Verbose {
		zerolog.SetGlobalLevel(zerolog.InfoLevel)
	} else {
		zerolog.SetGlobalLevel(zerolog.WarnLevel)
	}

	log.Info().Msg("🚀 Astrago Helm Chart Image Extractor 시작")
	log.Info().Str("helmfile", cfg.HelmfilePath).Msg("Helmfile 경로")
	log.Info().Str("environment", cfg.Environment).Msg("환경")
	log.Info().Str("output", cfg.OutputPath).Msg("출력 파일")

	// 2. 차트 발견
	log.Info().Msg("[1/4] 차트 자동 발견 중...")
	discoverer := discovery.New(cfg)
	charts, err := discoverer.Discover()
	if err != nil {
		return fmt.Errorf("차트 발견 실패: %w", err)
	}
	log.Info().Int("count", len(charts)).Msg("차트 발견 완료")

	// 3. 차트 렌더링
	log.Info().Msg("[2/4] 차트 렌더링 중...")
	helmRenderer := renderer.New(cfg)
	results, err := helmRenderer.RenderAll(charts)
	if err != nil {
		return fmt.Errorf("렌더링 실패: %w", err)
	}

	// Count successful renders
	successCount := 0
	for _, r := range results {
		if r.Error == nil {
			successCount++
		}
	}
	log.Info().
		Int("success", successCount).
		Int("total", len(results)).
		Msg("차트 렌더링 완료")

	// 4. 이미지 추출
	log.Info().Msg("[3/4] 이미지 추출 중...")
	imageExtractor := extractor.New(cfg)
	images := imageExtractor.Extract(results, charts)
	log.Info().Int("count", len(images)).Msg("이미지 추출 완료")

	// 5. 결과 출력
	log.Info().Msg("[4/4] 결과 저장 중...")
	writer := output.New(cfg)
	if err := writer.Write(images); err != nil {
		return fmt.Errorf("출력 실패: %w", err)
	}

	// 6. 다운로드 스크립트 생성 (옵션)
	generateScript, _ := cmd.Flags().GetBool("generate-script")
	if generateScript {
		log.Info().Msg("[추가] 다운로드 스크립트 생성 중...")
		scriptWriter := output.NewScriptWriter(cfg)
		if err := scriptWriter.WriteDownloadScript(images); err != nil {
			log.Warn().Err(err).Msg("스크립트 생성 실패")
		}
	}

	// 7. 리포트 생성 (옵션)
	generateReport, _ := cmd.Flags().GetBool("generate-report")
	if generateReport {
		log.Info().Msg("[추가] 상세 리포트 생성 중...")
		reportWriter := output.NewReportWriter(cfg)
		executionTime := time.Since(startTime)
		report, err := reportWriter.GenerateReport(charts, results, images, executionTime)
		if err != nil {
			log.Warn().Err(err).Msg("리포트 생성 실패")
		} else {
			if err := reportWriter.WriteReport(report); err != nil {
				log.Warn().Err(err).Msg("리포트 저장 실패")
			}
		}
	}

	executionTime := time.Since(startTime)
	log.Info().
		Dur("duration", executionTime).
		Int("images", len(images)).
		Msg("✅ 이미지 추출 완료!")

	return nil
}
